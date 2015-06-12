# -*- mode: makefile-gmake; tab-width: 4; -*-
# Makefile for decoder setup. Builds an actual system
# By Ulrich Germann

# Required: (1) parallel data; I recommend and assume below that all
#               text files are compressed with bzip2. This can be
#               adjusted, see zipped, zipper below.
#
#               ! one pair of files per corpus:
#                 <name>.${L1}[.bz2] and <name>.${L2}[.bz2] 
#
#               ! the base names of the files MUST EXACTLY match the
#                 corpus ids used by the context bias server
#
#               ! all files ending in ${L1}[.bz2] must have a matching
#                 counterpart ${L2}[.bz2]
# 
#               ! the files must be tokenized and in the desired case;
#                 this Makefile performs no preprocessing of data.
#
#               ! the files must also be 'cleaned' for alignment, i.e.
#
#                 - no empty sentences or sentences with more than N
#                   words (giza usually limits N to 80, fast_align can
#                   easily handle N = 120) I haven't tried out yet
#                   where exactly things break down. Symal seems to be
#                   the weakest link in the fast_align tool chain.
#
#                 - no pairs with excessive differences in length. A
#                   typical cut-off is to remove pairs where
#                   len(longer) > 9 * len(shorter).
#
#                 * scripts/filter-corpus.py can be used to filter
#                   compressed corpora. The traditional tool is
#                   clean-corpus.perl somewhere in the Moses scripts
#                   directory.
#
#           (2) a pre-built language model
#           (3) a working recent moses installation 
#           (4) my version of fast_align. A static executable is
#               available at:
# http://statmt.org/~germann/binaries/fast_align/fast_align-12-June-2015

# Change this if you want to use gzip or no compression at all.
# Note: With the speed of modern processors, disk access is the bottleneck,
#       so processing uncompressed files is likely to take longer.
zipped = .bz2
zipper = bzip2
zipcmd = $(addprefix |, $(zipper))

# Special for mvp 0.2.1
,:=, 
bias_server_url = http://api-test.mymemory.translated.net/getContextSimilarity.php
bias_parameters = of=json&language=english&ids=$(subst +,$(,),$(corpus))&context=

# L1: language you are translating FROM
# L2: language you are translating INTO
L1 ?= en
L2 ?= it

# LM Specification:
#
# lm.type:  IRSTLM or KENLM
# lm.order: ngram order
# lm.path:  complete absolute path to lm file
#
# Note: the language model will not be copied or moved, so the best
# thing is to put it where it should eventually go and specify that 
# path in lm.path below.
lm.type  ?= 
lm.order ?= 
lm.path  ?= 

# DATADIR: contains the parallel data (see (1) above!)
DATADIR    = /where/the/parallel/data/is

# DESTINATIONS
# MDL_DIR: memory-mapped bitexts and related files
# CFG_DIR: where the moses.ini file goes
PREFIX    = $(CURDIR)
MDL_DIR   = $(PREFIX)/mdl
CFG_DIR   = $(PREFIX)/cfg
moses.ini = $(CFG_DIR)/moses.ini
# WORKING DIRECTORY (files can be deleted afterwards) 
# Note: word alignment output also goes here. It can be reconstructed
# from the memory-mapped files, but you may want to keep if if you
# need it for other purposes.  The moses decoder won't need any of the
# files in here to work properly
WDIR = ./tmp

# Where are the necessary tools?

MOSES_ROOT   = 
MOSES_BIN   ?= $(MOSES_ROOT)/bin
mtt-build   ?= $(MOSES_BIN)/mtt-build
symal       ?= $(MOSES_BIN)/symal -a=g -d=yes -f=yes -b=yes
symal2mam   ?= $(MOSES_BIN)/symal2mam
mmlex-build ?= $(MOSES_BIN)/mmlex-build
fast_align  ?= $(MOSES_BIN)/fast_align -d -v -o
# Note: fast_align is not part of the moses distribution and needs to
# be installed separately. Since compilation requires gcc-4.8 (too recent for 
# many machines), I provide a compiled static binary here:
# http://statmt.org/~germann/binaries/fast_align/fast_align-12-June-2015
# My github repo is here: https://github.com/ugermann/fast_align
# This Makefile requires MY version of fast_align, which can read the two 
# sides of the corpus directly from two zipped files, instead of requiring
# writing everything into yet another text file first.

# FEATURE WEIGTHS FOR MOSES
# Note: the weights given here have worked reasonably well in practice but may
# have to be retuned. 
weights  = WordPenalty0= -0.0872494\n
weights += PhrasePenalty0= 0.0211538\n
weights += Distortion0= 0.0181195\n
weights += LM0= 0.0674919\n
weights += PT0= 0.0103713 0.00511969 0.0581561 0.0400955\n
weights += DM0= 0.0249098 0.0534396 0.103262 0.0463501 0.300834 0.0473231 0.0646575 0.0514668\n

################################################################################
#          YOU SHOULD NOT (HAVE TO) CHANGE ANYTHING BELOW THIS LINE
################################################################################

shards  = $(wildcard $(DATADIR)/*.${L1}$(zipped))
shards := $(sort $(patsubst %.${L1}$(zipped),%,$(notdir $(shards))))
# hack to replace spaces with + 
space := 
space += 
corpus := $(subst $(space),+,$(shards))

ifeq ($(words ($shards)),1)
TXT1 = $(DATADIR)/$(corpus).${L1}$(zipped)
TXT2 = $(DATADIR)/$(corpus).${L2}$(zipped)
else
TXT1 = $(WDIR)/$(corpus).${L1}$(zipped)
TXT2 = $(WDIR)/$(corpus).${L2}$(zipped)
parts1 := $(wildcard $(addsuffix .${L1}$(zipped),$(addprefix $(DATADIR)/,$(shards))))
parts2 := $(wildcard $(addsuffix .${L2}$(zipped),$(addprefix $(DATADIR)/,$(shards))))
ifneq ($(patsubst %.${L1}$(zipped),$(parts1)),$(parts2))
$(error "Text files don't match.")
endif
$(TXT1): 
	mkdir $@.tmp
	cat $(parts1) > $@.tmp/${@F}
	mv $@.tmp/${@F} $@
	rmdir $@.tmp

$(TXT2):
	mkdir $@.tmp
	cat $(parts2) > $@.tmp/${@F}
	mv $@.tmp/${@F} $@
	rmdir $@.tmp
endif

# only for KENLM
ifeq ($(lm.type),KENLM)
lm.lazyken = lazyken=1
endif

ALN_FWD = $(WDIR)/$(corpus).${L1}-${L2}.fwd$(zipped)
ALN_BWD = $(WDIR)/$(corpus).${L1}-${L2}.bwd$(zipped)
MCTBase = $(PREFIX)/mdl/$(corpus)
MCT1    = $(MCTBase).${L1}.mct
MCT2    = $(MCTBase).${L2}.mct
MAM     = $(MCTBase).${L1}-${L2}.mam
MMLEX   = $(MCTBase).${L1}-${L2}.lex
SYMAL   = $(DATADIR)/$(corpus).${L1}-${L2}.symal$(zipped)
.SECONDARY: # keep all files created

$(SYMAL): | $(ALN_FWD) $(ALN_BWD)
	mkdir $@.tmp
	scripts/fast-align2bal.py $(TXT1) $(TXT) $(ALN_FWD) $(ALN_BWD) \
	$(zipcmd) > $@.tmp/${@F} && mv $@.tmp/${@F} $@
	rmdir $@.tmp

$(ALN_FWD) : | $(TXT1) $(TXT2)
	mkdir $@.tmp
	$(fast_align) $(TXT1) $(TXT2) $(zipcmd) > $@.tmp/${@F} && mv $@.tmp/${@F} $@
	rmdir $@.tmp

$(ALN_BWD) : | $(TXT1) $(TXT2)
	mkdir $@.tmp
	$(fast_align) -r $(TXT1) $(TXT2) $(zipcmd) > $@.tmp/${@F} && mv $@.tmp/${@F} $@
	rmdir $@.tmp

$(MCT1): | $(TXT1)
	mkdir $@.tmp
	$(mtt-build) -i < $(TXT1) -o $@.tmp/$(corpus).${L1} && mv $@.tmp/* ${@D}
	rmdir $@.tmp

$(MCT2): | $(TXT2)
	mkdir $@.tmp
	$(mtt-build) -i < $(TXT2) -o $@.tmp/$(corpus).${L2} && mv $@.tmp/* ${@D}
	rmdir $@.tmp

$(MAM): | $(SYMAL)
	mkdir $@.tmp
	zcat -f $(SYMAL) | $(symal2mam) $@.tmp/${@F} && mv $@.tmp/${@F} $@
	rmdir $@.tmp

$(MMLEX): | $(MCT1) $(MCT2) $(MAM)
	mkdir $@.tmp
	$(mmlex-build) $(MCTBase). ${L1} ${L2} -o $@.tmp/${@F} && mv $@.tmp/${@F} $@
	rmdir $@.tmp

################################################################################
#                      CONSTRUCT THE MOSES.INI FILE
################################################################################

# Phrase table entry in moses.ini
ptline   = Mmsapt name=PT0 path=$(MCTBase) L1=${L1} L2=${L2} 
ptline  += output-factor=0 sample=1000 workers=1 
ptline  += pfwd=g pbwd=g logcnt=0 coh=0 prov=0 rare=0 unal=0 
ptline  += smooth=.01 lexalpha=0 lr-func=DM0
ptline  += bias-loglevel=0 bias-server=$(bias_server_url)?$(bias_parameters)

# Lexical reordering model in moses.ini
lrline   = LexicalReordering name=DM0 input-factor=0 output-factor=0
lrline  += type=hier-mslr-bidirectional-fe-allff

# Language model
lmline   = ${lm.type} name=LM0 path=${lm.path} order=${lm.order} 
lmline  += factor=0 num-features=0 ${lm.lazyken}

initext  = [input-factors]\n0\n\n
initext += [search-algorithm]\n1\n\n
initext += [stack]\n5000\n\n
initext += [cube-pruning-pop-limit]\n5000\n\n
initext += [mapping]\n0 T 0\n\n
initext += [distortion-limit]\n6\n\n
initext += [v]\n0\n\n
initext += [feature]\n
initext += UnknownWordPenalty\n
initext += WordPenalty\n
initext += Distortion\n
initext += PhrasePenalty\n
initext += $(ptline)\n
initext += $(lrline)\n
initext += $(lmline)\n\n
initext += [weight]\n$(weights)\n

# remove leading spaces
initext := $(subst \n$(space),\n,$(initext))

info:
	@echo -e '$(initext)'

$(moses.ini): | ${lm.path} $(MCT1) $(MCT2) $(MAM) $(MMLEX)
	mkdir $@.tmp
	echo -e $(initext) >> $@.tmp/${@F} && mv $@.tmp/${@F} $@
	rmidr $@.tmp