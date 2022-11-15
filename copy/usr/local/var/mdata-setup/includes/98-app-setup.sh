#!/usr/bin/bash

MAIL_UID=$(/native/usr/sbin/mdata-get mail_auth_user)
MAIL_PWD=$(/native/usr/sbin/mdata-get mail_auth_pass)
MAIL_HOST=$(/native/usr/sbin/mdata-get mail_smarthost)

MASTADON_DOMAIN=$(/native/usr/sbin/mdata-get mastadon_domain)
MASTADON_FROM=$(/native/usr/sbin/mdata-get mastadon_from)

# SECRET_KEY_BASE=$(su - mastodon -c "cd /home/mastodon/live; RAILS_ENV=production /home/mastodon/.rbenv/shims/bundle exec /home/mastodon/.rbenv/shims/rake secret")
# OTP_SECRET=
# VAPID_PRIVATE_KEY=
# VAPID_PUBLIC_KEY=

cat > /home/mastodon/live/.env.production << EOF
# https://docs.joinmastodon.org/admin/config/

LOCAL_DOMAIN=${MASTADON_DOMAIN}
SINGLE_USER_MODE=true
SECRET_KEY_BASE=${SECRET_KEY_BASE}
OTP_SECRET=${OTP_SECRET}
VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}
VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}
DB_HOST=/var/run/postgresql
DB_PORT=5432
DB_NAME=mastodon_production
DB_USER=mastodon
DB_PASS=
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
SMTP_SERVER=${MAIL_HOST}
SMTP_PORT=587
SMTP_LOGIN=${MAIL_UID}
SMTP_PASSWORD=${MAIL_PWD}
SMTP_AUTH_METHOD=plain
SMTP_OPENSSL_VERIFY_MODE=none
SMTP_FROM_ADDRESS=${MASTADON_FROM}
RAILS_LOG_LEVEL=error
DEFAULT_LOCALE=de
# TRUSTED_PROXY_IP=
# USER_ACTIVE_DAYS=2
# MAX_SESSION_ACTIVATIONS=10
EOF
chown mastodon:mastodon /home/mastodon/live/.env.production
chmod 0600 /home/mastodon/live/.env.production

# RAILS_ENV=production bundle exec rake mastodon:setup

su - mastodon -c "cd /home/mastodon/live; RAILS_ENV=production bundle exec rails db:setup"
su - mastodon -c "cd /home/mastodon/live; RAILS_ENV=production bundle exec rails assets:precompile"

systemctl enable --now mastodon-web mastodon-sidekiq mastodon-streaming
