#!/usr/bin/bash

mdata-delete mail_auth_pass || true

mdata-delete mastodon_admin_name  || true
mdata-delete mastodon_admin_email || true
mdata-delete mastodon_admin_pwd   || true

apt-get -y purge git make gcc g++ build-essential || true
apt-get -y autoremove || true
