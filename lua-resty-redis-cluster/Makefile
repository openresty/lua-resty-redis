OPENRESTY_PREFIX=/usr/local/openresty

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua
INSTALL ?= install

CMPFLAG       = -c -fPIC
LINKFLAG      = -shared
.PHONY: all test install clean

all: lib/resty/libredis_slot.so

clean:
    rm -rf lib/resty/*.so lib/resty/*.o

lib/resty/redis_slot.o:lib/resty/redis_slot.c
    $(CC) $(CMPFLAG) -o $@ $^

lib/resty/libredis_slot.so:lib/resty/redis_slot.o
    $(CC) $(LINKFLAG) -o $@ $^

install: all
    $(INSTALL) -d $(LUA_LIB_DIR)/resty
    $(INSTALL) lib/resty/*.lua $(LUA_LIB_DIR)/resty
    $(INSTALL) lib/resty/libredis_slot.so $(LUA_LIB_DIR)/libredis_slot.so

test: all
    PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -I../test-nginx/lib -r t
