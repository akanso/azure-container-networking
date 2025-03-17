import json
import os
import re
from pytimeparse import parse
import sys

def tryint(s):
    try:
        return int(s)
    except:
        return s

def alphanum_key(s):
    """ Turn a string into a list of string and number chunks.
        "z23a" -> ["z", 23, "a"]
    """
    return [ tryint(c) for c in re.split('([0-9]+)', s) ]

def sort_nicely(l):
    """ Sort the given list in the way that humans expect.
    """
    l.sort(key=alphanum_key)

def read_file(fn, isNode):
    """
    Reads file f and returns [CPU, Mem]
    """
    print("File: " + fn)
    totCPU=0
    totMem=0
    count=0

    cpuInd = 2
    memInd = 3
    if isNode:
        cpuInd = 1
        count = -1

    f = open(fn)
    for line in f.readlines():
        if isNode and count == -1:
            count += 1
            continue
        pline = line.split()
        if pline[1].startswith("cilium-operator"):
            totCPU += 0
            totMem += 0
        else:
            totCPU += int(pline[cpuInd][0:len(pline[cpuInd])-1])
            totMem += int(pline[memInd][0:len(pline[memInd])-2])
            count += 1
    print(count)
    return (totCPU / count), (totMem / count)

def main():
    dirnames = os.listdir(os.getcwd())
    sort_nicely(dirnames)
    writefile = open("parsed-metrics.csv", "w") # Don't forget to close
    writefile.write("Node CPU, Node Mem, Cilium CPU, Cilium Mem, FQDN CPU, FQDN Mem\n")
    # Get directories
    for i, dirname in enumerate(dirnames):
        # Skip this file
        if dirname.startswith("parse"):
            break
        # Get files in directory
        filenames = os.listdir(dirname)
        res=[""] * 6
        for j, filename in enumerate(filenames):
            cpu, mem = read_file(os.path.join(os.getcwd(), dirname, filename), filename.startswith("node"))
            if filename.startswith("custom"):
                res[4] = cpu
                res[5] = mem
            elif filename.startswith("node"):
                res[0] = cpu
                res[1] = mem
            elif filename.startswith("pod"):
                res[2] = cpu
                res[3] = mem
            else:
                print("Unknown file: " + filename)
        for j, resel in enumerate(res):
            if j == 0:
                writefile.write(str(resel))
            else:
                writefile.write("," + str(resel))
        writefile.write("\n")

if __name__ == "__main__":
    main()