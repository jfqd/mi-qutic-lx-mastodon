#!/usr/bin/bash

systemctl daemon-reload
pg_createcluster 15 main --start || true
su - postgres -c "psql -c \"CREATE USER mastodon CREATEDB;\"" || true

echo "* Setup postgresql backup"
mkdir -p /var/lib/postgresql/backups
chown postgres:postgres /var/lib/postgresql/backups
echo "0 1 * * * /usr/local/bin/psql_backup" >> /var/spool/cron/crontabs/postgres
echo "0 2 1 * * /usr/bin/vacuumdb --all" >> /var/spool/cron/crontabs/postgres
chown postgres:crontab /var/spool/cron/crontabs/postgres

# see: /home/mastodon/live/lib/tasks/mastodon.rake
# RAILS_ENV=production bundle exec rake mastodon:setup
cat > /home/mastodon/setup << "EOF"
#!/usr/bin/bash

cd /home/mastodon/live
export RAILS_ENV=production
# export PATH=/home/mastodon/.rbenv/shims:/home/mastodon/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
# 
# eval "$(rbenv init -)"

echo "*** generate SECRET_KEY_BASE"
SECRET_KEY_BASE=$(bundle exec rails runner "puts SecureRandom.hex(64)")

echo "*** generate OTP_SECRET"
OTP_SECRET=$(bundle exec rails runner "puts SecureRandom.hex(64)")

echo "*** generate VAPID"
VAPID=$(bundle exec rails mastodon:webpush:generate_vapid_key)
VAPID_PRIVATE_KEY=$(env $VAPID |grep VAPID_PRIVATE_KEY |sed "s|VAPID_PRIVATE_KEY=||")
VAPID_PUBLIC_KEY=$(env $VAPID |grep VAPID_PUBLIC_KEY |sed "s|VAPID_PUBLIC_KEY=||")

echo "*** generate env"
cat > /home/mastodon/live/.env.production << EOF2
# https://docs.joinmastodon.org/admin/config/

LOCAL_DOMAIN=
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
SMTP_SERVER=
SMTP_PORT=587
SMTP_LOGIN=
SMTP_PASSWORD=
SMTP_AUTH_METHOD=plain
SMTP_OPENSSL_VERIFY_MODE=none
SMTP_FROM_ADDRESS=
RAILS_LOG_LEVEL=error
DEFAULT_LOCALE=de
# TRUSTED_PROXY_IP=
# USER_ACTIVE_DAYS=2
# MAX_SESSION_ACTIVATIONS=10
EOF2
chmod 0600 /home/mastodon/live/.env.production

echo "*** create admin user"
bundle exec rails runner "username = 'MASTODON_ADMIN_NAME'; email = 'MASTODON_ADMIN_EMAIL'; password = 'MASTODON_ADMIN_PWD'; owner_role = UserRole.find_by(name: 'Owner'); user = User.new(email: email, password: password, confirmed_at: Time.now.utc, account_attributes: { username: username }, bypass_invite_request_check: true, role: owner_role); user.save(validate: false)

echo "*** setup db"
bundle exec rails db:setup

echo "*** precompile assets"
bundle exec rails assets:precompile

EOF
chmod +x /home/mastodon/setup

MASTADON_DOMAIN=$(/native/usr/sbin/mdata-get mastadon_domain)
MASTADON_FROM=$(/native/usr/sbin/mdata-get mastadon_from)

MASTODON_ADMIN_NAME=$(/native/usr/sbin/mdata-get mastadon_admin_name)
MASTODON_ADMIN_EMAIL=$(/native/usr/sbin/mdata-get mastadon_admin_email)
MASTODON_ADMIN_PWD=$(/native/usr/sbin/mdata-get mastadon_admin_pwd)

MAIL_UID=$(/native/usr/sbin/mdata-get mail_auth_user)
MAIL_PWD=$(/native/usr/sbin/mdata-get mail_auth_pass)
MAIL_HOST=$(/native/usr/sbin/mdata-get mail_smarthost)

sed -i \
    -e "s|LOCAL_DOMAIN=|LOCAL_DOMAIN=${MASTADON_DOMAIN}|" \
    -e "s|SMTP_FROM_ADDRESS=|SMTP_FROM_ADDRESS=${MASTADON_FROM}|" \
    -e "s|MASTODON_ADMIN_NAME|${MASTODON_ADMIN_NAME}|" \
    -e "s|MASTODON_ADMIN_EMAIL|${MASTODON_ADMIN_EMAIL}|" \
    -e "s|MASTODON_ADMIN_PWD|${MASTODON_ADMIN_PWD}|" \
    -e "s|SMTP_SERVER=|SMTP_SERVER=${MAIL_HOST}|" \
    -e "s|SMTP_LOGIN=|SMTP_LOGIN=${MAIL_UID}|" \
    -e "s|SMTP_PASSWORD=|SMTP_PASSWORD=${MAIL_PWD}|" \
    /home/mastodon/live/.env.production

echo "* Setup mastodon"
# su - mastodon -c "/home/mastodon/setup"
# rm /home/mastodon/setup

# systemctl enable --now mastodon-web mastodon-sidekiq mastodon-streaming
