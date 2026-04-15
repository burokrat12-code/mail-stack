FROM alpine:3.20

RUN apk add --no-cache \
    postfix \
    dovecot \
    dovecot-lmtpd \
    dovecot-pigeonhole-plugin \
    rspamd \
    redis \
    supervisor \
    bash \
    ca-certificates \
    opendkim \
    opendkim-utils \
    tzdata \
    gettext \
    sed \
    grep

# системные директории
RUN mkdir -p \
    /etc/rspamd \
    /var/lib/rspamd \
    /var/run/rspamd \
    /var/log/rspamd \
    /var/spool/postfix \
    /var/spool/postfix/private \
    /var/mail/vhosts/default.local/user \
    /etc/opendkim/keys/template \
    /etc/dovecot/conf.d \
    /etc/postfix/templates

# пользователи
RUN addgroup -S mail && adduser -S mail -G mail || true \
 && addgroup -S postfix && adduser -S postfix -G postfix || true \
 && addgroup -S dovecot && adduser -S dovecot -G dovecot || true

# права на mail storage
RUN chown -R dovecot:mail /var/mail/vhosts

# Postfix → LMTP доставка в Dovecot
RUN postconf -e "mailbox_transport=lmtp:unix:private/lmtp"

# Dovecot конфиг maildir
RUN printf "mail_location = maildir:/var/mail/vhosts/%%d/%%n/Maildir\n" \
"mail_home = /var/mail/vhosts/%%d/%%n\n" \
"mail_uid = dovecot\n" \
"mail_gid = mail\n" \
"mail_privileged_group = mail\n" \
"mail_full_filesystem_access = yes\n" \
"namespace inbox {\n  inbox = yes\n  mailbox Drafts {\n    special_use = \\Drafts\n  }\n  mailbox Junk {\n    special_use = \\Junk\n  }\n  mailbox Sent {\n    special_use = \\Sent\n  }\n  mailbox Trash {\n    special_use = \\Trash\n  }\n}\n" \
> /etc/dovecot/conf.d/10-mail.conf

# bootstrap базовой структуры
RUN mkdir -p \
    /var/mail/vhosts/default.local/user/Maildir/cur \
    /var/mail/vhosts/default.local/user/Maildir/new \
    /var/mail/vhosts/default.local/user/Maildir/tmp \
 && chown -R dovecot:mail /var/mail/vhosts

# Шаблон main.cf с переменными
RUN cat > /etc/postfix/templates/main.cf.tpl << 'EOF'
myhostname = ${HOSTNAME:-mail.${DOMAIN:-cargo-port.eu}}
mydomain = ${DOMAIN:-cargo-port.eu}
myorigin = $mydomain

mydestination = $myhostname, localhost.$mydomain, localhost, $mydomain

inet_interfaces = all
inet_protocols = ipv4

mynetworks = 127.0.0.0/8, 192.168.254.0/24

relayhost = ${RELAYHOST:-[smtp.gmail.com]:587}

smtp_sasl_auth_enable = yes
smtp_sasl_mechanism_filter = plain, login
smtp_sasl_security_options = noanonymous

smtp_tls_security_level = encrypt
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

smtpd_tls_security_level = may
smtpd_tls_auth_only = yes

smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_security_options = noanonymous

smtpd_recipient_restrictions = 
    permit_mynetworks
    permit_sasl_authenticated
    reject_unauth_destination

home_mailbox = Maildir/
mailbox_transport = lmtp:unix:private/lmtp

smtpd_milters = inet:localhost:8891,inet:localhost:11332
non_smtpd_milters = inet:localhost:8891

compatibility_level = 3.9
EOF

# Шаблон opendkim.conf
RUN cat > /etc/opendkim.conf.tpl << 'EOF'
Domain                  ${DOMAIN:-cargo-port.eu}
KeyFile                 /etc/opendkim/keys/${DOMAIN:-cargo-port.eu}/mail.private
Selector                mail
Socket                  inet:8891@localhost
UserID                  root
EOF

# Скрипт инициализации
RUN cat > /etc/init.sh << 'EOF'
#!/bin/sh

# Загружаем переменные окружения
DOMAIN=${DOMAIN:-cargo-port.eu}
HOSTNAME=${HOSTNAME:-mail.$DOMAIN}
RELAYHOST=${RELAYHOST:-[smtp.gmail.com]:587}

echo "Initializing mail stack for domain: $DOMAIN"

# Генерация main.cf из шаблона
envsubst < /etc/postfix/templates/main.cf.tpl > /etc/postfix/main.cf

# Генерация opendkim.conf из шаблона
envsubst < /etc/opendkim.conf.tpl > /etc/opendkim.conf

# Создание ключей DKIM
if [ ! -f /etc/opendkim/keys/$DOMAIN/mail.private ]; then
    echo "Generating DKIM keys for $DOMAIN"
    mkdir -p /etc/opendkim/keys/$DOMAIN
    cd /etc/opendkim/keys/$DOMAIN
    opendkim-genkey -s mail -d $DOMAIN
    echo "=== DKIM DNS record for $DOMAIN ==="
    cat mail.txt
    echo "=================================="
fi

# Исправление прав
chmod 755 /etc /etc/opendkim /etc/opendkim/keys
chmod 755 /etc/opendkim/keys/$DOMAIN
chmod 600 /etc/opendkim/keys/$DOMAIN/mail.private

# Запуск OpenDKIM
/usr/sbin/opendkim -f -x /etc/opendkim.conf &

# Настройка SASL пароля для Gmail (если передан)
if [ ! -z "$GMAIL_AUTH" ]; then
    echo "$RELAYHOST    $GMAIL_AUTH" > /etc/postfix/sasl_passwd
    chmod 600 /etc/postfix/sasl_passwd
    postmap lmdb:/etc/postfix/sasl_passwd
fi

# Перезапуск Postfix для применения конфига
postfix reload

echo "Mail stack initialized"
EOF

RUN chmod +x /etc/init.sh

COPY supervisord.conf /etc/supervisord.conf

EXPOSE 25 587 143 993

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
