PPATH=A4092
PROJECT=A4092
KIBOT_CONF=kibot/release.kibot.yaml
GERBER_OUTPUT=../Gerbers

DRILLS=$(GERBER_OUTPUT)/$(PROJECT)-NPTH.drl $(GERBER_OUTPUT)/$(PROJECT)-PTH.drl

GERBERS=$(GERBER_OUTPUT)/$(PROJECT)-B_Cu.gbl $(GERBER_OUTPUT)/$(PROJECT)-B_Mask.gbs $(GERBER_OUTPUT)/$(PROJECT)-B_Silkscreen.gbo $(GERBER_OUTPUT)/$(PROJECT)-Edge_Cuts.gm1 $(GERBER_OUTPUT)/$(PROJECT)-F_Cu.gtl $(GERBER_OUTPUT)/$(PROJECT)-F_Mask.gts $(GERBER_OUTPUT)/$(PROJECT)-F_Silkscreen.gto $(GERBER_OUTPUT)/$(PROJECT)-F_Paste.gtp $(GERBER_OUTPUT)/$(PROJECT)-B_Paste.gbp $(DRILLS)

JLCPCB=$(GERBER_OUTPUT)/$(PROJECT)_bom_jlc.csv $(GERBER_OUTPUT)/$(PROJECT)_cpl_jlc.csv
BOM=../Docs/$(PROJECT)_bom.html

.PHONY: release


all:	$(GERBERS) $(JLCPCB) $(BOM) ../Docs/Schematic.pdf ../Docs/$(PROJECT)-ibom.html ../Docs/$(PROJECT)-PCB.png ../Docs/$(PROJECT)-PCB-3D.png

schematic: ../Docs/Schematic.pdf
gerbers: $(GERBERS)
jlcpcb: $(JLCPCB)
bom: $(BOM)
ibom: ../Docs/$(PROJECT)-ibom.html
images: ../Docs/$(PROJECT)-PCB.png ../Docs/$(PROJECT)-PCB-3D.png

$(GERBERS):	$(PPATH)/$(PROJECT).kicad_pcb
	kibot -e ${PPATH}/${PROJECT}.kicad_sch -c $(KIBOT_CONF) Gerbers Drills

../Docs/$(PROJECT)-PCB.png ../Docs/$(PROJECT)-PCB-3D.png:	$(PPATH)/$(PROJECT).kicad_pcb
	kibot -e ${PPATH}/${PROJECT}.kicad_sch -s all -c $(KIBOT_CONF) Image 3dImage

$(JLCPCB): $(PPATH)/$(PROJECT).kicad_pcb $(PPATH)/$(PROJECT).kicad_sch
	kibot -e ${PPATH}/${PROJECT}.kicad_sch --skip-pre all -c $(KIBOT_CONF) JLCPCB_position JLCPCB_bom

../Docs/Schematic.pdf:	$(PPATH)/$(PROJECT).kicad_sch
	kibot -e ${PPATH}/${PROJECT}.kicad_sch -s all -c $(KIBOT_CONF) Schematic

../Docs/$(PROJECT)-ibom.html:	$(PPATH)/$(PROJECT).kicad_pcb
	kibot -e ${PPATH}/${PROJECT}.kicad_sch -s all -c $(KIBOT_CONF) IBOM

$(BOM): $(PPATH)/$(PROJECT).kicad_pcb $(PPATH)/$(PROJECT).kicad_sch
	kibot -e ${PPATH}/${PROJECT}.kicad_sch --skip-pre all -c $(KIBOT_CONF) html_bom
