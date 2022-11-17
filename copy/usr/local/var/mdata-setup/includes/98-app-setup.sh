#!/usr/bin/bash

echo "* Start postgresql"
systemctl daemon-reload
pg_createcluster 15 main --start || true
su - postgres -c "psql -c \"CREATE USER mastodon CREATEDB;\"" || true

echo "* Setup postgresql backup"
mkdir -p /var/lib/postgresql/backups
chown postgres:postgres /var/lib/postgresql/backups
echo "0 1 * * * /usr/local/bin/psql_backup" >> /var/spool/cron/crontabs/postgres
echo "0 2 1 * * /usr/bin/vacuumdb --all" >> /var/spool/cron/crontabs/postgres
chown postgres:crontab /var/spool/cron/crontabs/postgres

echo "* Setup mastodon"
# see: /home/mastodon/live/lib/tasks/mastodon.rake
# RAILS_ENV=production bundle exec rake mastodon:setup
cat > /home/mastodon/setup << "EOF"
#!/usr/bin/bash

cd /home/mastodon/live
export RAILS_ENV=production
export PATH=/home/mastodon/.rbenv/shims:/home/mastodon/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
eval "$(rbenv init -)"

cat > /home/mastodon/live/lib/tasks/mibe.rake << EOF2
namespace :mibe do
  desc 'Configure the instance for production use'
  task :secure_random do
    puts SecureRandom.hex(64)
  end
  desc 'Configure the instance for production use'
  task :generate_vapid_key do
    vapid_key = Webpush.generate_key
    puts "VAPID_PRIVATE_KEY=#{vapid_key.private_key}"
    puts "VAPID_PUBLIC_KEY=#{vapid_key.public_key}"
  end
end
EOF2

echo "*** generate SECRET_KEY_BASE"
SECRET_KEY_BASE=$(bundle exec rake mibe:secure_random)

echo "*** generate OTP_SECRET"
OTP_SECRET=$(bundle exec rake mibe:secure_random)

echo "*** generate VAPID"
VAPID=$(bundle exec rake mibe:generate_vapid_key)
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

EOF
chown mastodon:mastodon /home/mastodon/setup
chmod +x /home/mastodon/setup
su - mastodon -c "/home/mastodon/setup"

MASTADON_DOMAIN=$(/native/usr/sbin/mdata-get mastadon_domain)
MASTADON_FROM=$(/native/usr/sbin/mdata-get mastadon_from)

MAIL_UID=$(/native/usr/sbin/mdata-get mail_auth_user)
MAIL_PWD=$(/native/usr/sbin/mdata-get mail_auth_pass)
MAIL_HOST=$(/native/usr/sbin/mdata-get mail_smarthost)

sed -i \
    -e "s|LOCAL_DOMAIN=|LOCAL_DOMAIN=${MASTADON_DOMAIN}|" \
    -e "s|SMTP_FROM_ADDRESS=|SMTP_FROM_ADDRESS=${MASTADON_FROM}|" \
    -e "s|SMTP_SERVER=|SMTP_SERVER=${MAIL_HOST}|" \
    -e "s|SMTP_LOGIN=|SMTP_LOGIN=${MAIL_UID}|" \
    -e "s|SMTP_PASSWORD=|SMTP_PASSWORD=${MAIL_PWD}|" \
    /home/mastodon/live/.env.production

MASTODON_ADMIN_NAME=$(/native/usr/sbin/mdata-get mastadon_admin_name)
MASTODON_ADMIN_EMAIL=$(/native/usr/sbin/mdata-get mastadon_admin_email)
MASTODON_ADMIN_PWD=$(/native/usr/sbin/mdata-get mastadon_admin_pwd)

cat > /home/mastodon/setup << "EOF"
#!/usr/bin/bash

cd /home/mastodon/live
export RAILS_ENV=production

echo "*** setup db"
bundle exec rails db:setup

echo "*** create admin user"
bundle exec rails runner "username = 'MASTODON_ADMIN_NAME'; email = 'MASTODON_ADMIN_EMAIL'; password = 'MASTODON_ADMIN_PWD'; owner_role = UserRole.find_by(name: 'Owner'); user = User.new(email: email, password: password, confirmed_at: Time.now.utc, account_attributes: { username: username }, bypass_invite_request_check: true, role: owner_role); user.save(validate: false)"

echo "*** precompile assets"
bundle exec rails assets:precompile || true
EOF

sed -i \
    -e "s|MASTODON_ADMIN_NAME|${MASTODON_ADMIN_NAME}|" \
    -e "s|MASTODON_ADMIN_EMAIL|${MASTODON_ADMIN_EMAIL}|" \
    -e "s|MASTODON_ADMIN_PWD|${MASTODON_ADMIN_PWD}|" \
    /home/mastodon/setup

echo "* Setup mastodon"
su - mastodon -c "/home/mastodon/setup"
rm /home/mastodon/setup

echo "* Start mastodon services"
systemctl enable --now mastodon-web || true
systemctl enable --now mastodon-sidekiq || true
systemctl enable --now mastodon-streaming || true
systemctl start mastodon-streaming || true

echo "* Fix hostname in nginx mastodon config"
sed -i \
    -e "s|example.com;|${MASTADON_DOMAIN}|g" \
    /etc/nginx/sites-enabled/mastodon

echo "* Create http-basic password for backup area"
if [[ ! -f /etc/nginx/.htpasswd ]]; then
  if /native/usr/sbin/mdata-get mastodon_backup_pwd 1>/dev/null 2>&1; then
    /native/usr/sbin/mdata-get mastodon_backup_pwd | shasum | awk '{print $1}' | htpasswd -c -i /etc/nginx/.htpasswd "mastodon-backup"
    chmod 0640 /etc/nginx/.htpasswd
    chown root:www-data /etc/nginx/.htpasswd
  fi
fi

systemctl restart nginx || true

exit 0