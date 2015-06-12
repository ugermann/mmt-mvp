# -*- mode: makefile; tab-width: 4; -*-
# Makefile for building the infrastructure for the MMT Minimum Viable Product
# By Ulrich Germann

SHELL = bash
sourceforge = http://downloads.sourceforge.net/project
github = http://github.com/moses-smt/mosesdecoder/tarball

fast_align_url = http://statmt.org/~germann/binaries/fast_align/fast_align-12-June-2015

all: mvp-v0.2.1
# mvp-v0.2.1: irstlm_version = irstlm-5.80.08
mvp-v0.2.1: irstlm_url   = $(sourceforge)/irstlm/irstlm/irstlm-5.80/irstlm-5.80.08.tgz
mvp-v0.2.1: cmph_url     = $(sourceforge)/cmph/cmph/cmph-2.0.tar.gz
mvp-v0.2.1: fast_align_url = http://statmt.org/~germann/binaries/fast_align/fast_align-12-June-2015
mvp-v0.2.1: moses-tag    = mmt-mvp-v0.2.1
mvp-v0.2.1: moses

# DIRECTORIES
# CWD: bit of a hack to get the nfs-accessible path instead of the local real path
# OPT: installation destination for 3-rd party libraries
CWD      := $(shell cd . && pwd)
OPT      := $(CWD)/opt

# RESOURCES
NUMCORES := $(shell echo $$(($$(grep -c ^processor < /proc/cpuinfo) + 1)))

# build sequence for building 3rd-party components
# $1: build directory
# $2: installation destination
build  = cd $1 && ./configure --prefix=$2 $3
build += && make -j${NUMCORES} && make -j${NUMCORES} install 

# getting and unpacking packages from sourceforge
# $1: resource url on sourceforge
# $2: where to unpack
sfget = mkdir -p $(dir $2) && cd $(dir $2) && wget -qO- $1 | tar xz

# INSTALLATION OF CMPH
CMPH = $(CWD)/code/$(shell basename ${cmph_url} .tar.gz)
cmph: | $(OPT)/bin/cmph
$(OPT)/bin/cmph: 
	$(call sfget,${cmph_url},${CMPH})
	$(call build,$(CMPH),$(OPT))

# INSTALLATION OF IRSTLM
irstlm_version = $(basename $(notdir $(irstlm_url)))
IRSTLM        = $(CWD)/code/$(irstlm_version)/trunk
irstlm: | $(OPT)/bin/build-lm.sh
$(OPT)/bin/build-lm.sh: 
	$(call sfget,${irstlm_url},$(shell dirname ${IRSTLM}))
	cd $(IRSTLM) && ./regenerate-makefiles.sh
	$(call build,${IRSTLM},$(OPT))
	rm -rf $(dir ${IRSTLM})

# DOWNLOAD OF PRE-COMPILED FAST_ALIGN
fastalign: | $(CWD)/bin/fast_align
$(CWD)/bin/fast_align:
	wget ${fast_align_url} && mv $(notdir ${fast_align_url}) $@
	chmod ugo+rx $@

# MOSES INSTALLATION
bjam  = ./bjam -j${NUMCORES} --with-mm --with-irstlm=$(OPT) --with-cmph=$(OPT)
bjam += link=static

moses: irstlm cmph fastalign
moses: MOSES = $(CWD)/code/${moses-tag}
moses: | $(CWD)/bin/moses
$(CWD)/bin/moses:
	mkdir -p $(CWD)/code
	-cd $(CWD)/code && mkdir ${moses-tag} && wget -qO- ${github}/${moses-tag} \
	| tar --strip-components=1 -C ${moses-tag} -xzf - 
	cd ${MOSES} && ${bjam}
	mkdir -p ${@D}
	ln $(MOSES)/bin/moses $@

