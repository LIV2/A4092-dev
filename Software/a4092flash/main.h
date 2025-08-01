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

#ifndef MAIN_H
#define MAIN_H

#define STR(s) #s      /* Turn s into a string literal without expanding macro definitions (however, \
                          if invoked from a macro, macro arguments are expanded). */
#define XSTR(s) STR(s) /* Turn s into a string literal after macro-expanding it. */

#define VERSION_STRING "$VER: a4092flash " XSTR(DEVICE_VERSION) "." XSTR(DEVICE_REVISION) " (" XSTR(BUILD_DATE) ") " XSTR(GIT_REF)
#define VERSION "a4092flash " XSTR(DEVICE_VERSION) "." XSTR(DEVICE_REVISION) " (" XSTR(BUILD_DATE) ") " XSTR(GIT_REF)

#undef FindConfigDev
// NDK 1.3 definition of FindConfigDev is incorrect which causes "makes pointer from integer without a cast" warning
struct ConfigDev* FindConfigDev(struct ConfigDev*, LONG, LONG);

// NDK 1.3 includes lacks these, so define them here
#ifdef __KICK13__
void ColdReboot(void);
struct DosList *LockDosList(ULONG);
struct DosList *NextDosEntry(struct DosList *, ULONG);
void *UnLockDosList(ULONG);
#endif

struct scsiBoard {
  struct ConfigDev *cd;
  volatile UBYTE *flashbase;
};

struct dosDev {
  struct MinNode mn;
  struct MsgPort *handler;
  char *name;
};

ULONG getFileSize(char *);
BOOL readFileToBuf(char *, void *);
BOOL writeFlashToFile(char *filename, ULONG romSize);
BOOL writeBufToFlash(struct scsiBoard *board, UBYTE *source, volatile UBYTE *dest, ULONG size);

#endif
