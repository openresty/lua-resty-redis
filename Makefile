OPENRESTY_PREFIX=/usr/local/openresty-debug

PREFIX ?=          $(shell pkg-config luajit --variable=prefix)
LUA_INCLUDE_DIR ?= $(shell pkg-config luajit --cflags-only-I)
LUA_LIB_DIR ?=     $(shell pkg-config luajit --variable=INSTALL_LMOD)
INSTALL ?= install

.PHONY: all test install

all: ;

install: all
	$(INSTALL) -d $(DESTDIR)$(LUA_LIB_DIR)/resty
	$(INSTALL) lib/resty/*.lua $(DESTDIR)$(LUA_LIB_DIR)/resty

test: all
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -I../test-nginx/lib -r t

