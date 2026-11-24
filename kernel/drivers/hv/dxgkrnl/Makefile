# SPDX-License-Identifier: GPL-2.0
# Makefile for the hyper-v compute device driver (dxgkrnl).

obj-m	+= dxgkrnl.o
dxgkrnl-y := dxgmodule.o hmgr.o misc.o dxgadapter.o ioctl.o dxgvmbus.o dxgprocess.o  dxgsyncfile.o

ccflags-y += -I$(src)/../../../include -include linux/vmalloc.h -include $(src)/gpupv_features.h
