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
    tzdata

# системные директории
RUN mkdir -p \
    /etc/rspamd \
    /var/lib/rspamd \
    /var/run/rspamd \
    /var/log/rspamd \
    /var/spool/postfix \
    /var/spool/postfix/private \
    /var/mail/vhosts/default.local/user \
    /etc/dovecot/conf.d

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

# bootstrap базовой структуры (на всякий случай)
RUN mkdir -p \
    /var/mail/vhosts/default.local/user/Maildir/cur \
    /var/mail/vhosts/default.local/user/Maildir/new \
    /var/mail/vhosts/default.local/user/Maildir/tmp \
 && chown -R dovecot:mail /var/mail/vhosts

COPY supervisord.conf /etc/supervisord.conf

EXPOSE 25 587 143 993

CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
