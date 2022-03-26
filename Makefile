
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
MK_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))

ARCH = x86_64

ifeq ($(UNAME_S),Linux)
	PLAT ?= linux
else
	PLAT ?= windows
	MK_PATH := $(subst /c/,C:/,$(MK_PATH))
endif

LUACLIBS := ../luaclibs/dist-$(PLAT)
LHA_DIST := dist

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

GCC_NAME ?= $(shell gcc -dumpmachine)
LUA_DATE = $(shell date '+%Y%m%d')
DIST_SUFFIX ?= -$(GCC_NAME).$(LUA_DATE)

WEBVIEW_ARCH = x64
ifeq (,$(findstring x86_64,$(GCC_NAME)))
  WEBVIEW_ARCH = x86
endif

main: dist-archive

show:
	@echo ARCH: $(ARCH)
	@echo PLAT: $(PLAT)
	@echo DIST_SUFFIX: $(DIST_SUFFIX)
	@echo UNAME_S: $(UNAME_S)
	@echo UNAME_M: $(UNAME_M)

dist-copy-linux:
	cp -u lha.sh $(LHA_DIST)/

dist-copy-windows:
	cp -u $(LUACLIBS)/lua*.$(SO) $(LHA_DIST)/bin/
	cp -u lha.bat $(LHA_DIST)/

dist-copy: dist-copy-$(PLAT)
	cp -u $(LUACLIBS)/lua$(EXE) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/cjson.$(SO) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/luv.$(SO) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/openssl.$(SO) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/serial.$(SO) $(LHA_DIST)/bin/
	cp -u $(LUACLIBS)/zlib.$(SO) $(LHA_DIST)/bin/
	cp -ru $(LUACLIBS)/sha1/ $(LHA_DIST)/lua/
	cp -u $(LUACLIBS)/XmlParser.lua $(LHA_DIST)/lua/
	cp -u $(LUACLIBS)/sha1.lua $(LHA_DIST)/lua/
	cp -ru $(LUACLIBS)/jls/ $(LHA_DIST)/lua/
	cp -ru lha/ $(LHA_DIST)/lua/
	cp -u *.lua $(LHA_DIST)/
	cp -ru extensions/ $(LHA_DIST)/
	cp -ru assets/ $(LHA_DIST)/extensions/web-base/

dist-clean:
	rm -rf $(LHA_DIST)

dist-prepare:
	-mkdir $(LHA_DIST)
	mkdir $(LHA_DIST)/bin
	mkdir $(LHA_DIST)/lua
	mkdir $(LHA_DIST)/work

dist: dist-clean dist-prepare dist-copy

dist.tar.gz:
	cd $(LHA_DIST) && tar --group=jls --owner=jls -zcvf lha$(DIST_SUFFIX).tar.gz *

dist.zip:
	cd $(LHA_DIST) && zip -r lha$(DIST_SUFFIX).zip *

dist-archive: dist dist$(ZIP)

.PHONY: dist
