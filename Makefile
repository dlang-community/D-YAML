
.PHONY: build install clean

build:
	dub build -b release

install: 
	mkdir -p $(DESTDIR)/usr/include/dyaml/dyaml
	mkdir -p $(DESTDIR)/usr/share/doc/dyaml
	install -Dm 644 libdyaml.a $(DESTDIR)/usr/lib/libdyaml.a
	install -Dm 644 source/yaml.d $(DESTDIR)/usr/include/dyaml/yaml.d
	install -Dm 644 source/dyaml/* $(DESTDIR)/usr/include/dyaml/dyaml/
	install -Dm 644 dyaml.pc $(DESTDIR)/usr/share/pkgconfig/dyaml.pc
	install -Dm 644 LICENSE_1_0.txt $(DESTDIR)/usr/share/licenses/dyaml-git/LICENSE
	cp -r doc/html $(DESTDIR)/usr/share/doc/dyaml
	dub fetch tinyendian -q --cache=local
	install -Dm 644 $(wildcard tinyendian-*)/tinyendian/source/tinyendian.d \
	       	$(DESTDIR)/usr/include/dyaml/tinyendian.d

clean: 
	rm libdyaml.a
	rm -rf tinyendian-*
