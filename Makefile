# *****************************************************************************
# * W E L C O M E
# *****************************************************************************
#
# Congratulations, you have arrived at the ownCloud
#
#
#   _______  _______________  _______ ___  _________
#   \      \ \_   _____/\   \/  /    |   \/   _____/
#   /   |   \ |    __)_  \     /|    |   /\_____  \ 
#  /    |    \|        \ /     \|    |  / /        \
#  \____|__  /_______  //___/\  \______/ /_______  /
#          \/        \/       \_/                \/ 
#
#
# This makefile serves as a self documenting starting point for nexus driven
# tasks. If you just want to get an instance up and running do a
#
#    make future
#
# And point your browser to https://owncloud.localhost:8443
#
# Otherwise, read on ...
#
# *****************************************************************************
# * I N T R O D U C T I O N
# *****************************************************************************
#
# This makefile contains a few sections marked by two star rows. Each section
# is used to group related commands in the nexus. It helps to have a basic
# understanding of makefiles. A good starting point is
# https://medium.freecodecamp.org/want-to-know-the-easiest-way-to-save-time-use-make-eec453adf7fe
#
#
# *****************************************************************************
# * E N V I R O N M E N T   V A R I A B L E S
# *****************************************************************************

# TODO get rid of CURRENT_UID, is only used by KOPANO AFAICT (jfd)
CURRENT_UID=$(shell id -u):$(shell id -g)

# *****************************************************************************
# * H E L P   M E C H A N I S M
# *****************************************************************************
#
# Makefile help mechanism taken from from https://gist.github.com/prwhite/8168133#gistcomment-1727513
#
# And add help text after each target name starting with '\#\#'
# A category can be added with @category

#COLORS
GREEN  := $(shell tput -Txterm setaf 2)
WHITE  := $(shell tput -Txterm setaf 7)
YELLOW := $(shell tput -Txterm setaf 3)
RESET  := $(shell tput -Txterm sgr0)

HELP_FUN = \
	%help; \
	while(<>) { push @{$$help{$$2 // 'options'}}, [$$1, $$3] if /^([a-zA-Z\-]+)\s*:.*\#\#(?:@([a-zA-Z\-]+))?\s(.*)$$/ }; \
	print "usage: make [target]\n\n"; \
	for (sort keys %help) { \
	print "${WHITE}$$_:${RESET}\n"; \
	for (@{$$help{$$_}}) { \
	$$sep = " " x (32 - length $$_->[0]); \
	print "  ${YELLOW}$$_->[0]${RESET}$$sep${GREEN}$$_->[1]${RESET}\n"; \
	}; \
	print "\n"; }

# *****************************************************************************
# * G E N E R A L
# *****************************************************************************

# render a dynamically generated help
help: ##@other Show this help
	@perl -e '$(HELP_FUN)' $(MAKEFILE_LIST)

# by default show the help
default: help

# *****************************************************************************
# * C O N T A I N E R S
# *****************************************************************************

# to build the future we need to bring up a dev environment
future: up ##@containers Start a development environment
# TODO open the browser, but switch depending on linux (xdgopen) or mac env (open)
#    xdg-open "https://owncloud.localhost:8443"
#    open "https://owncloud.localhost:8443"

.PHONY: up
# FIXME we need to checkout the src of phoenix befor building the containers or building the container for reva fails
up: start-eos reva-src phoenix-src reva-container phoenix-container ##@containers docker-compose up all containers
	CURRENT_UID=$(CURRENT_UID) docker-compose -f deploy/core.yml -f deploy/storage/eos.yml up -d

# to test litmus we need to use basic auth. the deploy/core-litmus.yml uses env vars to override the necessary config
.PHONY: up-litmus
up-litmus: start-eos reva-container phoenix-container ##@containers docker-compose up all containers, but use basic auth
	CURRENT_UID=$(CURRENT_UID) docker-compose -f deploy/core-litmus.yml -f deploy/storage/eos.yml up -d

.PHONY: down
# TODO split up so we can up/down eos & reva individually?
down: stop-eos ##@containers docker-compose down all containers
	CURRENT_UID=$(CURRENT_UID) docker-compose -f deploy/core.yml -f deploy/storage/eos.yml down

.PHONY: logs
logs: ##@containers show and follow nexus container logs
	docker-compose -f deploy/core.yml -f deploy/storage/eos.yml logs -f

# *****************************************************************************
# * R E V A
# *****************************************************************************
#
# While reva can be used to start all reva services in one container we start
# individual containers to be able to only show u subset of the extensive
# logging generated by reva. Have a look at the deploy/*.yml docker-compose 
# files for more details on what config us used for which container.

.PHONY: reva-container
reva-container: reva-src ##@reva Build a docker container for reva, the storage
	docker-compose -f deploy/core.yml -f deploy/storage/eos.yml build authsvc ocdavsvc storageprovidersvc

.PHONY: reva-rebuild
reva-rebuild: reva-rebuild-auth reva-rebuild-ocdav reva-rebuild-storage ##@reva Rebuild and restart all reva based containers

.PHONY: reva-rebuild-auth
reva-rebuild-auth: ##@reva Rebuild and restart the storage container without bringing down the nexus
	docker-compose -f deploy/core.yml -f deploy/storage/eos.yml up -d --no-deps --build authsvc

.PHONY: reva-rebuild-ocdav
reva-rebuild-ocdav: ##@reva Rebuild and restart the storage container without bringing down the nexus
	docker-compose -f deploy/core.yml -f deploy/storage/eos.yml up -d --no-deps --build ocdavsvc

.PHONY: reva-rebuild-storage
reva-rebuild-storage: ##@reva Rebuild and restart the storage container without bringing down the nexus
	docker-compose -f deploy/core.yml -f deploy/storage/eos.yml up -d --no-deps --build storageprovidersvc

reva-src: build/reva/src ##@reva Get reva sources
build/reva/src:
	git clone git@github.com:owncloud/reva.git build/reva/src 
	cd build/reva/src; \
	git checkout nexus; \
	git remote add upstream git@github.com:cernbox/reva.git

# *****************************************************************************
# * P H O E N I X
# *****************************************************************************
# TODO rework the phoenix container so it uses yarn watch to automatically redeploy changes
.PHONY: phoenix-container
phoenix-container: phoenix-src ##@phoenix Build a docker container for phoenix, the web frontend
	docker-compose -f deploy/core.yml build phoenix

phoenix-src: build/phoenix/src ##@phoenix Get phoenix sources
build/phoenix/src:
	git clone git@github.com:owncloud/phoenix.git build/phoenix/src

# *****************************************************************************
# * E O S
# *****************************************************************************
# The currrent storage layer for the nexus
#
# For more information go to https://eos.web.cern.ch/
# Technical docs can be found at http://eos-docs.web.cern.ch/eos-docs/

.PHONY: start-eos
start-eos: eos-src ##@eos Start EOS services
	# TODO find a way to properly inject the EOS_UTF8 env var into the container
	# EOS_UTF8=1 enables utf8 filenames
	# EOS_SYNCTIME_ACCOUNTING=1 enables mtime propagation
	# TODO there does not seem to be etag propagation
	sed -i "s/--name eos-mgm-test --net/--name eos-mgm-test --env EOS_UTF8=1 --env EOS_NS_ACCOUNTING=1 --env EOS_SYNCTIME_ACCOUNTING=1 --net/" ./build/eos-docker/src/scripts/start_services.sh
	./build/eos-docker/src/scripts/start_services.sh -i gitlab-registry.cern.ch/dss/eos:4.4.25 -n 1
	# TODO find a way to provision users on the fly
	docker exec -i eos-mgm-test eos mkdir eos/dockertest/aaliyah_adams
	# make daemon the owner of the file ...
	# TODO clarify: the sss auth seems to force user daemon to do everything, eos -r 0 0 or eos -r 1500 1500 does not change the actual user
	docker exec -i eos-mgm-test eos chown 2:99 eos/dockertest/aaliyah_adams

.PHONY: stop-eos
stop-eos: eos-src ##@eos Stop EOS services
	./build/eos-docker/src/scripts/shutdown_services.sh

eos-src: build/eos-docker/src ##@eos Get EOS docker sources
build/eos-docker/src: 
	git clone https://gitlab.cern.ch/eos/eos-docker.git build/eos-docker/src

# *****************************************************************************
# * C L E A N U P
# *****************************************************************************

.PHONY: clean
clean: clean-containers clean-src ##@cleanup Cleanup sources and containers

.PHONY: clean-containers
clean-containers: ##@cleanup Stop and cleanup containers
	CURRENT_UID=$(CURRENT_UID) docker-compose -f deploy/storage/eos.yml -f deploy/core.yml rm -s

.PHONY: clean
clean-src: ##@cleanup Cleanup sources
	rm -rf build/reva/src
	rm -rf build/phoenix/src

# *****************************************************************************
# * T E S T S
# *****************************************************************************


.PHONY: test-litmus
test-litmus: ##@tests run litmus tests - requires an instance with basic auth credential strategy
	# FIXME mounting the folder 'litmus' does not work from within the makefile
	docker run -e LITMUS_URL="http://ocdavsvc:9998/remote.php/webdav/" -e LITMUS_USERNAME=aaliyah_adams -e LITMUS_PASSWORD=secret --network=deploy_ocis -v "$(pwd)"/litmus:/root owncloud/litmus
