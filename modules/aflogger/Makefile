# af_logger — AF/lens/TTL telemetry (AFLG block emitter)
#
# Linear: TIN-1228 (Sprint C2). See README.rst for status.

MODULE_NAME = aflogger
MODULE_OBJS = $(BUILD_DIR)/aflogger.o
TOP_DIR = ../..

include $(TOP_DIR)/modules/Makefile
.DEFAULT_GOAL := $(BUILD_DIR)/module_complete

# AFLG block lives in mlv_rec's header; pull it in.
CFLAGS += -I$(TOP_DIR)/modules/raw_video/mlv_rec
