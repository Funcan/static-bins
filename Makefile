include versions.env

TOOLS := strace lsof zsh

.PHONY: all
all: $(TOOLS)

TOOLCHAIN_IMAGE ?= static-bins-toolchain
# Each toolchain stage is a full GCC build. Locally, build them one at a time so they
# fit in a small Docker VM; in CI (CI=true) let BuildKit build them in parallel.
SERIAL ?= $(if $(CI),,1)
TOOLCHAIN_STAGES := x86_64 i686 aarch64 arm

# Behind an SSL-intercepting proxy, the CA bundle is passed to the build as a secret.
ifneq ($(CURL_CA_BUNDLE),)
EXTRA_CA_SECRET := --secret id=extra_ca,src=$(CURL_CA_BUNDLE)
endif

DOCKER_BUILD_TOOLCHAIN = docker build \
	  --build-arg DEBIAN_IMAGE=$(DEBIAN_IMAGE) \
	  --build-arg MUSL_CROSS_MAKE_REF=$(MUSL_CROSS_MAKE_REF) \
	  --build-arg GCC_VER=$(GCC_VER) \
	  --build-arg MUSL_VER=$(MUSL_VER) \
	  --build-arg BINUTILS_VER=$(BINUTILS_VER) \
	  --build-arg LINUX_VER=$(LINUX_VER) \
	  $(EXTRA_CA_SECRET) toolchain

.PHONY: toolchain
toolchain:
ifneq ($(SERIAL),)
	for stage in $(TOOLCHAIN_STAGES); do $(DOCKER_BUILD_TOOLCHAIN) --target $$stage || exit 1; done
endif
	$(DOCKER_BUILD_TOOLCHAIN) -t $(TOOLCHAIN_IMAGE)

ARCHES ?= x86_64 i686 aarch64 arm

ifneq ($(CURL_CA_BUNDLE),)
EXTRA_CA_MOUNT := -v $(CURL_CA_BUNDLE):/etc/extra-ca.pem:ro -e CURL_CA_BUNDLE=/etc/extra-ca.pem
endif
RUN_TOOLCHAIN = docker run --rm --user $$(id -u):$$(id -g) $(EXTRA_CA_MOUNT) \
	  -v $(CURDIR):/src:ro -v $(CURDIR)/out:/out $(TOOLCHAIN_IMAGE)

.PHONY: strace
strace: toolchain
	mkdir -p out
	$(RUN_TOOLCHAIN) sh /src/tools/strace/build.sh $(STRACE_VERSION) $(ARCHES)

.PHONY: lsof
lsof: toolchain
	mkdir -p out
	$(RUN_TOOLCHAIN) sh /src/tools/lsof/build.sh $(LSOF_VERSION) $(LSOF_SHA256) $(ARCHES)

.PHONY: zsh
zsh: toolchain
	mkdir -p out
	$(RUN_TOOLCHAIN) sh /src/tools/zsh/build.sh $(ZSH_VERSION) $(NCURSES_VERSION) $(ARCHES)

.PHONY: clean
clean:
	rm -rf out

# Also removes the toolchain image and Docker's build cache, forcing a full toolchain
# rebuild. The prune can't be scoped to this project: it clears ALL build cache.
.PHONY: distclean
distclean: clean
	-docker image rm $(TOOLCHAIN_IMAGE)
	docker builder prune -f
