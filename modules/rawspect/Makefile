# raw_spectral — per-frame calibration metadata (RAWX block emitter)
#
# Linear: TIN-1222 (Sprint B2). See README.rst for status.

MODULE_NAME = rawspect
MODULE_OBJS = $(BUILD_DIR)/raw_spectral.o
TOP_DIR = ../..

include $(TOP_DIR)/modules/Makefile
.DEFAULT_GOAL := $(BUILD_DIR)/module_complete

# RAWX block lives in mlv_rec's header; pull it in.
CFLAGS += -I$(TOP_DIR)/modules/raw_video/mlv_rec
