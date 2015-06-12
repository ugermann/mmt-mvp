#!/usr/bin/env python 
# Filters parallel corpus for word alignment 
# Author: Ulrich Germann
# to do: add options for pre- and post-processing pipes

import os, sys, argparse, gzip, bz2
from subprocess import Popen, PIPE

min_length =   1
max_length = 120
max_ratio  =   9

desc = "Filters parallel corpus for word alignment"
P = argparse.ArgumentParser(description=desc)

P.add_argument("--max-ratio", "-r", help="Max sentence length ratio (%d)"%max_ratio, 
               type=int, default=max_ratio)

P.add_argument("-v", "--verbose", action='store_true')
P.add_argument("infile1")
P.add_argument("infile2")
P.add_argument("outfile1")
P.add_argument("outfile2")

# TO DO: allow user to specify pre- and post-processing pipes
# P.add_argument("--preproc1")
# P.add_argument("--preproc2")
# P.add_argument("--postproc1")
# P.add_argument("--postproc2")

# P.add_argument("--max-length", help="Maximum sentence length (%d)"%max_length,
#                type=int, default=80)
# P.add_argument("--min-length", help="Maximum sentence length (%d)"%min_length,
#                type=int, default=min_length)

P.add_argument("--length", "-L", type=str, default="%d-%d"%(min_length,max_length),
               help="Sentence length range (%d-%d)"%(min_length,max_length))
               


def magic_open(fname,mode):
    if fname[-3:] == ".gz" or fname[-4:] == ".gz_": 
        return gzip.open(fname,mode)
    if fname[-4:] == ".bz2" or fname[-5:] == ".bz2_": 
        return bz2.BZ2File(fname,mode)
    return open(fname,mode)

opts = P.parse_args(sys.argv[1:])
min_length, max_length = [int(x) for x in opts.length.split('-')]
max_ratio = opts.max_ratio

in1  = magic_open(opts.infile1,'r')
in2  = magic_open(opts.infile2,'r')
out1 = magic_open(opts.outfile1+'_','w')
out2 = magic_open(opts.outfile2+'_','w')

good_words1     = 0
good_words2     = 0
total_words1    = 0
total_words2    = 0
good_lines      = 0
total_lines     = 0
line1_too_short = 0
line2_too_short = 0
line1_too_long  = 0
line2_too_long  = 0
ratio_error1    = 0
ratio_error2    = 0
for line1 in in1:
    line2 = in2.readline()
    total_lines += 1
    if opts.verbose and total_lines % 1000 == 0:
        if total_lines % 50000 == 0: 
            sys.stderr.write("%10dK\n"%(total_lines/1000))
        else:
            sys.stderr.write(".")
            pass
        pass
    slen1 = len(line1.strip().split())
    slen2 = len(line2.strip().split())
    total_words1 += slen1
    total_words2 += slen2
    errcnt = 0

    if   slen1 < min_length: 
        errcnt += 1
        line1_too_short += 1
    elif slen1 > max_length: 
        errcnt += 1
        line1_too_long  += 1
        pass

    if   slen2 < min_length: 
        errcnt += 1
        line2_too_short += 1
    elif slen2 > max_length: 
        errcnt += 1
        line2_too_long  += 1
        pass

    if   slen1 > max_ratio * slen2: 
        errcnt += 1
        ratio_error1 += 1
    elif slen2 > max_ratio * slen1: 
        errcnt += 1
        ratio_error2 += 1
        pass

    if errcnt: continue

    out1.write(line1)
    out2.write(line2)
    good_lines  += 1
    good_words1 += slen1
    good_words2 += slen2
    pass

if opts.verbose:
    sys.stderr.write("\n")

bad_words1 = total_words1 - good_words1
bad_words2 = total_words2 - good_words2
bad_lines  = total_lines  - good_lines
print "%20s %10s %10s %10s"%\
    ("","sent. pairs", "words L1", "words L2")
print "%20s %10d %10d %10d"%\
    ("   processed:", total_lines, total_words1, total_words2)
print "%20s %10d %10d %10d"%\
    ("    retained:", good_lines, good_words1, good_words2)
print "%20s %10d %10d %10d"%\
    ("filtered out:", bad_lines, bad_words1, bad_words2)
print 
print "%20s %10s %10s %10s"%\
    ("violations","too short", "too long", "ratio > %d"%max_ratio)
print "%20s %10d %10d %10d"%\
    ("segment 1:", line1_too_short, line1_too_long, ratio_error1)
print "%20s %10d %10d %10d"%\
    ("segment 2:", line2_too_short, line2_too_long, ratio_error2)

out1.close()
out2.close()
os.rename(opts.outfile1+'_', opts.outfile1)
os.rename(opts.outfile2+'_', opts.outfile2)
sys.exit(0)
