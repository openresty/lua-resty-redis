OPENRESTY_PREFIX=/usr/local/openresty-debug
.PHONY: all test

all: ;

test:
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -I../test-nginx/lib -r t

install: all
	cp -r lib/resty $(OPENRESTY_PREFIX)/lualib/

