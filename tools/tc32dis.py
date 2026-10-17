#!/usr/bin/env python3
"""極簡 TC32(Telink)反組譯器,純 Python、無相依,用來讀 8 Pro 散熱器的韌體映像。

用法:  python3 -I tools/tc32dis.py <映像.bin> <起始位址> <結束位址>
例:    python3 -I tools/tc32dis.py Firmware/b6ae73....bin 0xc8a0 0xc900

指令格式取自 Telink 官方 objdump 的 Thumb 衍生指令表,該表由
https://github.com/trust1995/Ghidra_TELink_TC32 (generate_sleigh.py) 抽出;這裡只重寫了解碼邏輯。
只涵蓋 16 位元指令與 32 位元 tjl(BL),tjlex 與少數格式未實作,遇到會印成 .short。
映像載入位址視為 0,所以印出的位址就是檔案偏移。靜態分析,未經實機驗證。
"""
import struct, sys, re
T=[(0x46c0,0xffff,'tnop'),(0x0000,0xffc0,'tand r0,r3'),(0x0040,0xffc0,'txor'),(0x0080,0xffc0,'tshftl'),(0x00c0,0xffc0,'tshftr'),
(0x0100,0xffc0,'tasr'),(0x0140,0xffc0,'taddc'),(0x0180,0xffc0,'tsubc'),(0x01c0,0xffc0,'trotr'),(0x0200,0xffc0,'tnand'),(0x0240,0xffc0,'tneg'),
(0x0280,0xffc0,'tcmp'),(0x02c0,0xffc0,'tcmpn'),(0x0300,0xffc0,'tor'),(0x0340,0xffc0,'tmul'),(0x0380,0xffc0,'tbclr'),(0x03c0,0xffc0,'tmovn')]
ALU={0x0000:'tand',0x0040:'txor',0x0080:'tshftl',0x00c0:'tshftr',0x0100:'tasr',0x0140:'taddc',0x0180:'tsubc',0x01c0:'trotr',0x0200:'tnand',
0x0240:'tneg',0x0280:'tcmp',0x02c0:'tcmpn',0x0300:'tor',0x0340:'tmul',0x0380:'tbclr',0x03c0:'tmovn'}
CC=['eq','ne','cs','cc','mi','pl','vs','vc','hi','ls','ge','lt','gt','le','al','']
def r(n): return {13:'sp',14:'lr',15:'pc'}.get(n,'r%d'%n)
def bits(h,lo,hi): return (h>>lo)&((1<<(hi-lo+1))-1)
def sx(v,n): return v-(1<<n) if v&(1<<(n-1)) else v
def lst(h,extra):
    l=[r(i) for i in range(8) if h>>i&1]
    if h&0x100 and extra: l.append(extra)
    return '{'+', '.join(l)+'}'
def dis(d,base=0):
    """yield (addr,size,text,comment)"""
    o=0;n=len(d)
    while o+1<n:
        h=struct.unpack_from('<H',d,o)[0];a=base+o;c=''
        # 32-bit BL
        if o+3<n and (h&0xf800)==0x9000:
            l=struct.unpack_from('<H',d,o+2)[0]
            if (l&0xf800)==0x9800:
                off=(sx(bits(h,0,10),11)<<12)+(bits(l,0,10)<<1)
                yield a,4,'tjl  0x%x'%(a+4+off),'';o+=4;continue
        t=None
        if h==0x46c0: t='tnop'
        elif (h&0xf800)==0xa000: t='tmovs %s, #%d'%(r(bits(h,8,10)),h&255)
        elif (h&0xf800)==0xa800: t='tcmp  %s, #%d'%(r(bits(h,8,10)),h&255)
        elif (h&0xf800)==0xb000: t='tadds %s, #%d'%(r(bits(h,8,10)),h&255)
        elif (h&0xf800)==0xb800: t='tsubs %s, #%d'%(r(bits(h,8,10)),h&255)
        elif (h&0xf800)==0x0800:
            ad=((a+4)&~3)+(h&255)*4
            v=struct.unpack_from('<I',d,ad-base)[0] if 0<=ad-base<=n-4 else None
            t='tloadr %s, [pc, #%d]'%(r(bits(h,8,10)),(h&255)*4);c='; [0x%x] = %s'%(ad,'0x%x'%v if v is not None else '?')
        elif (h&0xfe00)==0x6400: t='tpush %s'%lst(h,'lr')
        elif (h&0xfe00)==0x6c00: t='tpop  %s'%lst(h,'pc')
        elif (h&0xfe00)==0x6800: t='treti %s'%lst(h,'pc')
        elif (h&0xff80)==0x6000: t='tadd  sp, #%d'%((h&0x7f)*4)
        elif (h&0xff80)==0x6080: t='tsub  sp, #%d'%((h&0x7f)*4)
        elif (h&0xfff8) in (0x6bc0,0x6bc8,0x6bd0,0x6bd8):
            t={0x6bc0:'tmcsr',0x6bc8:'tmrcs',0x6bd0:'tmssr',0x6bd8:'tmrss'}[h&0xfff8]+' '+r(h&7)
        elif (h&0xff80)==0x0700: t='tjex  %s'%r(bits(h,3,6))
        elif (h&0xff00) in (0x0400,0x0500,0x0600):
            nm={0x0400:'tadd',0x0500:'tcmp',0x0600:'tmov'}[h&0xff00]
            t='%s  %s, %s'%(nm,r((h&7)|((h>>4)&8)),r(bits(h,3,6)))
        elif (h&0xffc0) in ALU and (h&0xff00)<0x0400: t='%s  %s, %s'%(ALU[h&0xffc0],r(h&7),r(bits(h,3,5)))
        elif (h&0xfe00)==0xe800: t='tadds %s, %s, %s'%(r(h&7),r(bits(h,3,5)),r(bits(h,6,8)))
        elif (h&0xfe00)==0xea00: t='tsubs %s, %s, %s'%(r(h&7),r(bits(h,3,5)),r(bits(h,6,8)))
        elif (h&0xfe00)==0xec00: t='tadds %s, %s, #%d'%(r(h&7),r(bits(h,3,5)),bits(h,6,8))
        elif (h&0xfe00)==0xee00: t='tsubs %s, %s, #%d'%(r(h&7),r(bits(h,3,5)),bits(h,6,8))
        elif (h&0xfe00)==0x1200: t='tstorerh %s, [%s, %s]'%(r(h&7),r(bits(h,3,5)),r(bits(h,6,8)))
        elif (h&0xfe00)==0x1a00: t='tloadrh %s, [%s, %s]'%(r(h&7),r(bits(h,3,5)),r(bits(h,6,8)))
        elif (h&0xf600)==0x1600: t='tloadrs%s %s, [%s, %s]'%('h' if h&0x800 else 'b',r(h&7),r(bits(h,3,5)),r(bits(h,6,8)))
        elif (h&0xfa00)==0x1000: t='tstorer%s %s, [%s, %s]'%('b' if h&0x400 else '',r(h&7),r(bits(h,3,5)),r(bits(h,6,8)))
        elif (h&0xfa00)==0x1800: t='tloadr%s %s, [%s, %s]'%('b' if h&0x400 else '',r(h&7),r(bits(h,3,5)),r(bits(h,6,8)))
        elif (h&0xf800)==0xf000: t='tshftl %s, %s, #%d'%(r(h&7),r(bits(h,3,5)),bits(h,6,10))
        elif (h&0xf800)==0xf800: t='tshftr %s, %s, #%d'%(r(h&7),r(bits(h,3,5)),bits(h,6,10) or 32)
        elif (h&0xf800)==0xe000: t='tasr %s, %s, #%d'%(r(h&7),r(bits(h,3,5)),bits(h,6,10) or 32)
        elif (h&0xf800)==0x5000: t='tstorer %s, [%s, #%d]'%(r(h&7),r(bits(h,3,5)),bits(h,6,10)*4)
        elif (h&0xf800)==0x5800: t='tloadr %s, [%s, #%d]'%(r(h&7),r(bits(h,3,5)),bits(h,6,10)*4)
        elif (h&0xf800)==0x4000: t='tstorerb %s, [%s, #%d]'%(r(h&7),r(bits(h,3,5)),bits(h,6,10))
        elif (h&0xf800)==0x4800: t='tloadrb %s, [%s, #%d]'%(r(h&7),r(bits(h,3,5)),bits(h,6,10))
        elif (h&0xf800)==0x2000: t='tstorerh %s, [%s, #%d]'%(r(h&7),r(bits(h,3,5)),bits(h,6,10)*2)
        elif (h&0xf800)==0x2800: t='tloadrh %s, [%s, #%d]'%(r(h&7),r(bits(h,3,5)),bits(h,6,10)*2)
        elif (h&0xf800)==0x3000: t='tstorer %s, [sp, #%d]'%(r(bits(h,8,10)),(h&255)*4)
        elif (h&0xf800)==0x3800: t='tloadr %s, [sp, #%d]'%(r(bits(h,8,10)),(h&255)*4)
        elif (h&0xf800)==0x7000: t='tadd %s, pc, #%d'%(r(bits(h,8,10)),(h&255)*4)
        elif (h&0xf800)==0x7800: t='tadd %s, sp, #%d'%(r(bits(h,8,10)),(h&255)*4)
        elif (h&0xf800)==0xd000: t='tstorem %s!, %s'%(r(bits(h,8,10)),lst(h&255,''))
        elif (h&0xf800)==0xd800: t='tloadm %s!, %s'%(r(bits(h,8,10)),lst(h&255,''))
        elif (h&0xff00)==0xcf00: t='tserv #%d'%(h&255)
        elif (h&0xf000)==0xc000:
            t='tj%s 0x%x'%(CC[bits(h,8,11)],a+4+(sx(h&255,8)<<1))
        elif (h&0xf800)==0x8000: t='tj  0x%x'%(a+4+(sx(h&0x7ff,11)<<1))
        else: t='.short 0x%04x'%h
        yield a,2,t,c;o+=2
if __name__=='__main__':
    if len(sys.argv)!=4: sys.exit(__doc__)
    f,s,e=sys.argv[1],int(sys.argv[2],0),int(sys.argv[3],0)
    full=open(f,'rb').read()
    for a,sz,t,c in dis(full,0):
        if s<=a<e: print('%05x  %-12s %s %s'%(a,full[a:a+sz].hex(' '),t,c))
