#!/usr/bin/bash

mdata-delete mail_smarthost || true
mdata-delete mail_auth_user || true
mdata-delete mail_auth_pass || true
mdata-delete mail_adminaddr || true

mdata-delete mastadon_domain      || true
mdata-delete mastadon_from        || true
mdata-delete mastadon_admin_name  || true
mdata-delete mastadon_admin_email || true
mdata-delete mastadon_admin_pwd   || true

apt-get -y purge git make gcc g++ build-essential || true
apt-get -y autoremove || true
