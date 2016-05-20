PROJECT = tepid
PROJECT_DESCRIPTION = Tansu Proxy Interface Daemon
PROJECT_VERSION = 0.0.1

DEPS = \
	cowboy \
	envy \
	gun \
	jsx \
	mdns \
	recon \
	shelly

dep_cowboy = git https://github.com/ninenines/cowboy.git 2.0.0-pre.3
dep_envy = git https://github.com/shortishly/envy.git master
dep_mdns = git https://github.com/shortishly/mdns.git master
dep_shelly = git https://github.com/shortishly/shelly.git master

SHELL_OPTS = \
	-boot start_sasl \
	-config dev.config \
	-mnesia dir db \
	-name $(PROJECT) \
	-s $(PROJECT) \
	-s rb \
	-s sync \
	-setcookie $(PROJECT)

SHELL_DEPS = \
	sync

include erlang.mk
