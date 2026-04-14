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

# базовые директории сервисов
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

# права на maildir
RUN chown -R dovecot:mail /var/mail/vhosts

# Postfix → LMTP доставка в Dovecot
RUN postconf -e "mailbox_transport=lmtp:unix:private/lmtp"

# Dovecot mail location
RUN printf "mail_location = maildir:/var/mail/vhosts/%%d/%%n/Maildir\nmail_privileged_group = mail\n" \
> /etc/dovecot/conf.d/10-mail.conf

COPY supervisord.conf /etc/supervisord.conf

EXPOSE 25 587 143 993

CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
