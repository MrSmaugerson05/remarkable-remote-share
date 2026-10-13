objects = main.o xovi.o
name = loopback-importer

CXXFLAGS += -D_GNU_SOURCE -fPIC `pkg-config --cflags-only-I Qt6Core Qt6Network`

$(name).so: $(objects)
	$(CXX) $(CXXFLAGS) -shared -Wl,--build-id=none,--strip-all -o $@ $(objects)

xovi.cpp xovi.h &: $(name).xovi ../../compatibility.env
	@set -eu; \
	version=$$(sed -n 's/^PROJECT_VERSION=//p' ../../compatibility.env); \
	printf '%s\n' "$$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+$$'; \
	definition=.$(name).generated.xovi; \
	trap 'rm -f "$$definition"' EXIT; \
	sed "s/^version PROJECT_VERSION$$/version $$version/" $(name).xovi > "$$definition"; \
	python3 $(XOVI_REPO)/util/xovigen.py -o xovi.cpp -H xovi.h "$$definition"

main.o: xovi.h main.cpp

.PHONY: clean
clean:
	rm -f $(name).so $(objects) xovi.cpp xovi.h .$(name).generated.xovi
