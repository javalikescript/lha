LUACLIBS := ../luaclibs/dist
LUAJLS := $(LUACLIBS)
LHA_DIST := dist

# make LUACLIBS=../luaclibs/dist-aarch64-pi LUAJLS=../luajls release

PLAT ?= $(shell grep ^platform $(LUACLIBS)/versions.txt | cut -f2)
TARGET_NAME ?= $(shell grep ^target $(LUACLIBS)/versions.txt | cut -f2)
RELEASE_DATE = $(shell date '+%Y%m%d')
RELEASE_NAME ?= -$(TARGET_NAME).$(RELEASE_DATE)

SO_windows=dll
EXE_windows=.exe
ZIP_windows=.zip

SO_linux=so
EXE_linux=
ZIP_linux=.tar.gz

SO := $(SO_$(PLAT))
EXE := $(EXE_$(PLAT))
MAIN_MK := $(MK_$(PLAT))
ZIP := $(ZIP_$(PLAT))

main: dist-archive

show:
	@echo PLAT: $(PLAT)
	@echo TARGET_NAME: $(TARGET_NAME)
	@echo RELEASE_DATE: $(RELEASE_DATE)
	@echo RELEASE_NAME: $(RELEASE_NAME)
	@echo LUACLIBS: $(LUACLIBS)
	@echo LUAJLS: $(LUAJLS)

dist-bin-linux:
	cp -u $(LUACLIBS)/linux.$(SO) $(LHA_DIST)/bin/

dist-bin-windows:
	cp -u $(LUACLIBS)/lua*.$(SO) $(LHA_DIST)/bin/
	-cp -u $(LUACLIBS)/win32.$(SO) $(FCUT_DIST_CLUA)/

dist-bin: dist-bin-$(PLAT)
	cp -u $(LUACLIBS)/lua$(EXE) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/cjson.$(SO) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/luv.$(SO) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/openssl.$(SO) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/serial.$(SO) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/zlib.$(SO) $(LHA_DIST)/bin/
	-cp -u $(LUACLIBS)/lpeg.$(SO) $(LHA_DIST)/bin/

dist-any:
	cp -ru $(LUACLIBS)/sha1/ $(LHA_DIST)/lua/
	cp -u $(LUACLIBS)/sha1.lua $(LHA_DIST)/lua/
	cp -u $(LUACLIBS)/XmlParser.lua $(LHA_DIST)/lua/
	cp -ru $(LUAJLS)/jls/ $(LHA_DIST)/lua/
	cp -ru lha/ $(LHA_DIST)/lua/
	cp -u lha.sh $(LHA_DIST)/
	cp -u lha.cmd $(LHA_DIST)/
	cp -u *.lua $(LHA_DIST)/
	cp -ru extensions/ $(LHA_DIST)/
	cp -ru assets/ $(LHA_DIST)/

dist-clean:
	rm -rf $(LHA_DIST)

dist-bin-prepare:
	mkdir $(LHA_DIST)/bin

dist-prepare:
	@echo Prepare release $(RELEASE_NAME) for $(PLAT)
	-mkdir $(LHA_DIST)
	mkdir $(LHA_DIST)/lua
	mkdir $(LHA_DIST)/work

dist: dist-clean dist-prepare dist-any

dist-full: dist dist-bin-prepare dist-bin

dist.tar.gz:
	cd $(LHA_DIST) && tar --group=jls --owner=jls -zcvf lha$(RELEASE_NAME).tar.gz *

dist.zip:
	cd $(LHA_DIST) && zip -q -r lha$(RELEASE_NAME).zip *

dist-archive: dist dist$(ZIP)

dist-full-archive release: dist-full dist$(ZIP)

.PHONY: dist
