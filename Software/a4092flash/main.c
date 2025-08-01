// SPDX-License-Identifier: GPL-2.0-only
/* This file is part of a4092flash
 * Copyright (C) 2023 Matthew Harlum <matt@harlum.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 2.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

#include <exec/execbase.h>
#include <proto/exec.h>
#include <proto/expansion.h>
#include <string.h>
#include <stdio.h>
#include <stdbool.h>
#include <proto/dos.h>
#include <dos/dos.h>
#include <proto/alib.h>
#include <dos/dosextens.h>

#include "flash.h"
#include "main.h"
#include "config.h"

#define MANUF_ID_COMMODORE_BRAUNSCHWEIG 513
#define MANUF_ID_COMMODORE 514

#define PROD_ID_A4092  84

const char ver[] = VERSION_STRING;

struct Library *DosBase;
struct ExecBase *SysBase;
struct ExpansionBase *ExpansionBase = NULL;
struct Config *config;
bool devsInhibited = false;

/**
 * _ColdReboot()
 *
 * Kickstart V36 (2.0+) and up contain a function for this
 * But for 1.3 we will need to provide our own function
 */
static void _ColdReboot(void)
{
  // Copied from coldboot.asm
  // http://amigadev.elowar.com/read/ADCD_2.1/Hardware_Manual_guide/node02E3.html
  asm("move.l  4,a6               \n\t" // SysBase
      "lea.l   DoIt(pc),a5        \n\t"
      "jsr     -0x1e(a6)          \n\t" // Call from Supervisor mode
      ".align 4                   \n\t" // Must be aligned!
      "DoIt:                      \n\t"
      "lea.l   0x1000000,a0       \n\t" // (ROM end)
      "sub.l   -0x14(a0),a0       \n\t" // (ROM end)-(ROM Size)
      "move.l  4(a0),a0           \n\t" // Initial PC
      "subq.l  #2,(a0)            \n\t" // Points to second RESET
      "reset                      \n\t"
      "jmp     (a0)");
}

/**
 * inhibitDosDevs
 * 
 * inhibit/uninhibit all drives
 * Send an ACTION_INHIBIT packet to all devices to flush the buffers to disk first
 * 
 * @param inhibit (bool) True: inhibit, False: uninhibit 
 */
bool inhibitDosDevs(bool inhibit)
{
  bool success = true;
  struct MsgPort *mp = CreatePort(NULL,0);
  struct Message msg;
  struct DosPacket __aligned packet;
  struct DosList *dl;
  struct dosDev *dd;

  struct MinList devs;
  NewList((struct List *)&devs);

  if (mp) {
    packet.dp_Port = mp;
    packet.dp_Link = &msg;
    msg.mn_Node.ln_Name = (char *)&packet;

    if (SysBase->SoftVer >= 36) {

      dl = LockDosList(LDF_DEVICES|LDF_READ);
      // Build a list of dos devices to inhibit
      // We need to send a packet to the FS to do the inhibit after releasing the lock
      // So build a list of devs to be (un)-inhibited
      while ((dl = NextDosEntry(dl,LDF_DEVICES))) {
        dd = AllocMem(sizeof(struct dosDev),MEMF_ANY|MEMF_CLEAR);
        if (dd) {
          if (dl->dol_Task) { // Device has a FS process?
            dd->handler = dl->dol_Task;
            AddTail((struct List *)&devs,(struct Node *)dd);
          }
        }
      }
      UnLockDosList(LDF_DEVICES|LDF_READ);

    } else {
      // For Kickstart 1.3
      // Build a list of dos devices the old fashioned way
      struct RootNode *rn = DOSBase->dl_Root;
      struct DosInfo *di = BADDR(rn->rn_Info);

      Forbid();
      // Build a list of dos devices to inhibit
      // We need to send a packet to the FS but that can't be done while in Forbid()
      // So build a list of devs to be (un)-inhibited
      for (dl = BADDR(di->di_DevInfo); dl; dl = BADDR(dl->dol_Next)) {
        if (dl->dol_Type == DLT_DEVICE && dl->dol_Task) {
          dd = AllocMem(sizeof(struct dosDev),MEMF_ANY|MEMF_CLEAR);
          if (dd) {
            if (dl->dol_Task) { // Device has a FS process?
              dd->handler = dl->dol_Task;
              AddTail((struct List *)&devs,(struct Node *)dd);
            }
          }
        }
      }
      Permit();
    }

    struct dosDev *next = NULL;
    // Send an ACTION_INHIBIT packet directly to the FS
    for (dd = (struct dosDev *)devs.mlh_Head; dd->mn.mln_Succ; dd = next) {
      if (inhibit) {
        packet.dp_Port = mp;
        packet.dp_Type = ACTION_FLUSH;
        PutMsg(dd->handler,&msg);
        WaitPort(mp);
        GetMsg(mp);
      }

      for (int t=0; t < 3; t++) {
        packet.dp_Port = mp;
        packet.dp_Type = ACTION_INHIBIT;
        packet.dp_Arg1 = (inhibit) ? DOSTRUE : DOSFALSE;
        PutMsg(dd->handler,&msg);
        WaitPort(mp);
        GetMsg(mp);

        if (packet.dp_Res1 == DOSTRUE || packet.dp_Res2 == ERROR_ACTION_NOT_KNOWN)
          break;

        Delay(1*TICKS_PER_SECOND);
      }

      if (packet.dp_Res1 == DOSFALSE && packet.dp_Res2 != ERROR_ACTION_NOT_KNOWN) {
        success = false;
      }

      next = (struct dosDev *)dd->mn.mln_Succ;
      Remove((struct Node *)dd);
      FreeMem(dd,sizeof(struct dosDev));

    }

    DeletePort(mp);

  } else {
    success = false;
  }

  return success;
}

/**
 * setup_a4092_board
 *
 * Configure the board struct for an A4092 Board
 * @param board pointer to the board struct
 */
static void setup_a4092_board(struct scsiBoard *board)
{
  board->flashbase = (volatile UBYTE *)board->cd->cd_BoardAddr;
}

/**
 * promptUser
 *
 * Ask if the user wants to update this board
 * @param config pointer to the config struct
 * @return boolean true / false
 */
static bool promptUser(struct Config *config)
{
  int c;
  char answer = 'y'; // Default to yes

  printf("Update this device? (Y)es/(n)o/(a)ll: ");

  if (config->assumeYes) {
    printf("y\n");
    return true;
  }

  while ((c = getchar()) != '\n' && c != EOF) answer = c;

  answer |= 0x20; // convert to lowercase;

  if (answer == 'a') {
    config->assumeYes = true;
    return true;
  }

  return (answer == 'y');
}

static BOOL probeFlash(ULONG romSize);

int main(int argc, char *argv[])
{
  SysBase = *((struct ExecBase **)4UL);
  DosBase = OpenLibrary("dos.library",0);

  int rc = 0;
  int boards_found = 0;

  void *driver_buffer = NULL;

  ULONG romSize    = 0;

  if (DosBase == NULL) {
    return(rc);
  }

  printf("\n%s\n\n", VERSION);

  struct Task *task = FindTask(0);
  SetTaskPri(task,20);
  if ((config = configure(argc,argv)) != NULL) {

    if (config->writeFlash && config->scsi_rom_filename) {
      romSize = getFileSize(config->scsi_rom_filename);
      if (romSize == 0) {
        rc = 5;
        goto exit;
      }

      if (romSize > 2048*1024) {
        printf("ROM file too large.\n");
        rc = 5;
        goto exit;
      }

      if (romSize < 64*1024) {
        printf("ROM file too small.\n");
        rc = 5;
        goto exit;
      }

      driver_buffer  = AllocMem(romSize,MEMF_ANY|MEMF_CLEAR);

      if (driver_buffer) {
        if (readFileToBuf(config->scsi_rom_filename,driver_buffer) == false) {
          rc = 5;
          goto exit;
        }
      } else {
        printf("Couldn't allocate memory.\n");
        rc = 5;
        goto exit;
      }
    }
   
    if (!inhibitDosDevs(true)) {
      printf("Failed to inhibit AmigaDOS volumes, wait for disk activity to stop and try again.\n");
      rc = 5;
      inhibitDosDevs(false);
      goto exit;
    };

    devsInhibited = true;

    if ((ExpansionBase = (struct ExpansionBase *)OpenLibrary("expansion.library",0)) != NULL) {

      struct ConfigDev *cd = NULL;
      struct scsiBoard board;

      while ((cd = FindConfigDev(cd,-1,-1)) != NULL) {

        board.cd = cd;

        switch (cd->cd_Rom.er_Manufacturer) {
          case MANUF_ID_COMMODORE:
          case MANUF_ID_COMMODORE_BRAUNSCHWEIG:
            if (cd->cd_Rom.er_Product == PROD_ID_A4092) {
              printf("Found A4091 / A4092");
              setup_a4092_board(&board);
              break;
            } else {
              continue; // Skip this board
            }

          default:
            continue; // Skip this board
        }

        printf(" at Address 0x%06x\n",(int)cd->cd_BoardAddr);
        boards_found++;

        // Ask the user if they wish to update this board
        if ((config->writeFlash || config->eraseFlash) && !promptUser(config)) continue;

        UBYTE manufId,devId;
        UWORD sectorSize;
        ULONG flashSize;

        if (flash_init(&manufId,&devId,board.flashbase,&flashSize,&sectorSize)) {
          if (config->eraseFlash) {
            printf("Erasing whole flash.\n");
            flash_erase_chip();
          }

          if (config->writeFlash && config->scsi_rom_filename) {
            if (config->eraseFlash == false) {
              if (sectorSize > 0) {
                printf("Erasing flash bank.\n");
                flash_erase_bank(sectorSize);
              } else {
                printf("Erasing whole flash.\n");
                flash_erase_chip();
              }
            }
            printf("Writing A4092 ROM image to flash memory.\n");
            writeBufToFlash(&board, driver_buffer, board.flashbase, romSize);
            printf("\n");
          }

	  if (config->readFlash && config->scsi_rom_filename && flashSize) {
            printf("Writing A4092 flash memory to file.\n");
            if (writeFlashToFile(config->scsi_rom_filename,flashSize) == false) {
              rc = 5;
              goto exit;
            }
	  }

	  if (config->probeFlash && flashSize) {
            if (probeFlash(flashSize) == false) {
              rc = 5;
              goto exit;
            }
	  }

        } else {
	  if (manufId == 0x9f && devId == 0xaf)
            printf("This is likely an A4091. Only A4092 has flash memory.\n");
	  else
            printf("Error: A4092 - Unknown Flash device Manufacturer: %02X Device: %02X\n", manufId, devId);
          rc = 5;
        }
      }

      if (boards_found == 0) {
        printf("No A4092 board(s) found\n");
      }
    } else {
      printf("Couldn't open Expansion.library.\n");
      rc = 5;
    }

    if (config->rebootRequired) {
      printf("Press return to reboot.\n");
      getchar();
      if (SysBase->SoftVer >= 36) {
        ColdReboot();
      } else {
        _ColdReboot();
      }
    }

    if (devsInhibited)
      inhibitDosDevs(false);

  } else {
    usage();
  }

exit:
  if (driver_buffer)  FreeMem(driver_buffer,romSize);
  if (config)         FreeMem(config,sizeof(struct Config));
  if (ExpansionBase)  CloseLibrary((struct Library *)ExpansionBase);
  if (DosBase)        CloseLibrary((struct Library *)DosBase);
  return (rc);
}

/**
 * getFileSize
 *
 * @brief return the size of a file in bytes
 * @param filename file to check the size of
 * @returns File size in bytes
*/
ULONG getFileSize(char *filename)
{
  BPTR fileLock;
  ULONG fileSize = 0;
  struct FileInfoBlock *FIB;

  FIB = (struct FileInfoBlock *)AllocMem(sizeof(struct FileInfoBlock),MEMF_CLEAR);

  if ((fileLock = Lock(filename,ACCESS_READ)) != 0) {

    if (Examine(fileLock,FIB)) {
      fileSize = FIB->fib_Size;
    }

  } else {
    printf("Error opening %s\n",filename);
    fileSize = 0;
  }

  if (fileLock) UnLock(fileLock);
  if (FIB) FreeMem(FIB,sizeof(struct FileInfoBlock));

  return (fileSize);
}

/**
 * readFileToBuF
 *
 * @brief Read the rom file to a buffer
 * @param filename Name of the file to open
 * @return true on success
*/
BOOL readFileToBuf(char *filename, void *buffer)
{
  ULONG romSize = getFileSize(filename);
  BOOL ret = true;

  if (romSize == 0) return false;

  BPTR fh;

  if (buffer) {
    fh = Open(filename,MODE_OLDFILE);

    if (fh) {
      Read(fh,buffer,romSize);
      Close(fh);
    } else {
      printf("Error opening %s\n",filename);
      return false;
    }

  } else {
    return false;
  }

  return ret;
}

/**
 * writeFlashToFile()
 *
 * Write the Flash content to the specified file
 *
 * @param filename file to write
 * @param size number of bytes to write
 * @returns true on success
*/
BOOL writeFlashToFile(char *filename, ULONG romSize)
{
  BOOL ret = true;
  char * buffer;

  if (romSize == 0) return false;
  fprintf (stdout, "Flash size: %d KB\n", romSize / 1024);
  buffer = AllocMem(romSize, 0);

  BPTR fh;

  if (buffer) {
    fprintf(stdout, "Reading Flash...\n");
    int i;
    for (i=0; i<romSize; i++) {
      buffer[i] = flash_readByte(i);
    }
    fprintf(stdout, "Writing File %s...\n", filename);
    fh = Open(filename,MODE_NEWFILE);

    if (fh) {
      Write(fh,buffer,romSize);
      Close(fh);
      FreeMem(buffer, romSize);
    } else {
      printf("Error opening %s\n",filename);
      FreeMem(buffer, romSize);
      return false;
    }

  } else {
    return false;
  }

  return ret;
}

/**
 * writeBufToFlash()
 *
 * Write the buffer to the currently selected flash bank
 *
 * @param source pointer to the source data
 * @param dest pointer to the flash base
 * @param size number of bytes to write
 * @returns true on success
*/
BOOL writeBufToFlash(struct scsiBoard *board, UBYTE *source, volatile UBYTE *dest, ULONG size)
{
  UBYTE *sourcePtr = NULL;
  UBYTE destVal   = 0;

  int progress = 0;
  int lastProgress = 1;

  fprintf(stdout,"Writing:     ");
  fflush(stdout);

  for (int i=0; i<size; i++) {

    progress = (i*100)/(size-1);

    if (lastProgress != progress) {
      fprintf(stdout,"\b\b\b\b%3d%%",progress);
      fflush(stdout);
      lastProgress = progress;
    }
    sourcePtr = ((void *)source + i);
    flash_writeByte(i,*sourcePtr);

  }

  fprintf(stdout,"\n");
  fflush(stdout);

  fprintf(stdout,"Verifying:     ");
  for (int i=0; i<size; i++) {

    progress = (i*100)/(size-1);

    if (lastProgress != progress) {
      fprintf(stdout,"\b\b\b\b%3d%%",progress);
      fflush(stdout);
      lastProgress = progress;
    }
    sourcePtr = ((void *)source + i);
    destVal = flash_readByte(i);
    if (*sourcePtr != destVal) {
          printf("\nVerification failed at offset %06x - Expected %02X but read %02X\n",i,*sourcePtr,destVal);
          return false;
    }
  }
  fprintf(stdout,"\n");
  fflush(stdout);
  return true;
}

static int find_a409x_version(const unsigned char *buffer, ULONG romSize) {
    const char *needle = "A4091 scsidisk";
    size_t needle_len = strlen(needle);

    // We can only search up to (romSize - needle_len)
    for (size_t i = 0; i <= romSize - needle_len; i++) {
        if (memcmp(buffer + i, needle, needle_len) == 0) {
            return (int)i;
        }
    }
    return -1; // Not found
}

/**
 * probeFlash()
 *
 * Analyze flash content
 *
 * @param size number of bytes to write
 * @returns true on success
*/
static BOOL probeFlash(ULONG romSize)
{
  BOOL ret = true;
  char * buffer;

  if (romSize == 0) return false;
  buffer = AllocMem(romSize, 0);

  if (buffer) {
    fprintf(stdout, "Reading Flash...\n");
    int i;
    for (i=0; i<romSize; i++) {
      buffer[i] = flash_readByte(i);
    }
    
    ULONG magic1,magic2;
    memcpy (&magic1, buffer+0x10000-8, 4);
    memcpy (&magic2, buffer+0x10000-4, 4);
    if (magic1 == 0xFFFF5352 && magic2 == 0x2F434448) {
      printf("Found 64KB A4091/A4092 image.\n");
    } else {
      printf("Not a standard image.\n");
    }

    int offset = find_a409x_version(buffer, romSize);
    if (offset > 0) {
      printf("Version: %s\n", buffer + offset);
    } else {
      printf("Could not determine version.\n");
    }

    FreeMem(buffer, romSize);
  } else {
    ret=false;
  }

  return ret;
}
