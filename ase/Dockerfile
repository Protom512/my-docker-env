FROM registry.access.redhat.com/ubi9/ubi-minimal:latest AS base
ENV LANG=C
RUN microdnf install -y shadow-utils tar gzip findutils\
    && useradd sybase \
    && mkdir /opt/sap

FROM base AS source
WORKDIR /tmp
RUN set -x \
    && curl -OLS https://d1cuw2q49dpd0p.cloudfront.net/ASE16/Current/ASE_Suite.linuxamd64.tgz \
    && mkdir -p /opt/tmp/ \
    && tar xfz ASE_Suite.linuxamd64.tgz -C /opt/tmp/ \
    && rm -rf ASE_Suite.linuxamd64.tgz

FROM busybox AS version
COPY --from=source /opt/tmp/archives/version.txt /

FROM source AS installer
ADD sap-response.txt /tmp/
RUN /opt/tmp/setup.bin -i silent \
    -f /tmp/sap-response.txt \
    -DAGREE_TO_SAP_LICENSE=true \
    -DRUN_SILENT=true
RUN touch /opt/sap/interfaces
RUN rm -rf \
        /opt/sap/ASE-16_1/bin/diagserver \
        /opt/sap/sybuninstall \
        /opt/sap/ASE-16_1/sample/ \
        /opt/sap/ASE-16_1/symlib/ \
    && find /opt/sap -type f \
        \( -name 'sqlupgrade*' -o -name 'sqlupgraderes*' -o -name 'preupgrade*' \) \
        -delete

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
ENV LANG=C
ARG TINI_VERSION=v0.19.0
WORKDIR /opt/sap
RUN microdnf install -y libaio pam procps-ng coreutils-single tar gzip shadow-utils  \
    && useradd sybase \
    && curl -fsSL -o /usr/local/bin/tini \
        "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-amd64" \
    && chmod +x /usr/local/bin/tini \
    && microdnf clean all
COPY --chown=sybase --from=installer /opt/sap/SYBASE.sh /opt/sap/
COPY --chown=sybase --from=installer /opt/sap/ASE-16_1/bin /opt/sap/ASE-16_1/bin
COPY --chown=sybase --from=installer /opt/sap/ASE-16_1/install /opt/sap/ASE-16_1/install
COPY --chown=sybase --from=installer /opt/sap/ASE-16_1/locales /opt/sap/ASE-16_1/locales
COPY --chown=sybase --from=installer /opt/sap/ASE-16_1/scripts /opt/sap/ASE-16_1/scripts
COPY --chown=sybase --from=installer /opt/sap/OCS-16_1/lib3p64 /opt/sap/OCS-16_1/lib3p64
COPY --chown=sybase --from=installer /opt/sap/OCS-16_1/bin /opt/sap/OCS-16_1/bin
COPY --chown=sybase --from=installer /opt/sap/OCS-16_1/lib /opt/sap/OCS-16_1/lib
COPY --chown=sybase --from=installer /opt/sap/charsets /opt/sap/charsets
COPY --chown=sybase --from=installer /opt/sap/locales /opt/sap/locales
COPY --chown=sybase --from=installer /opt/sap/config /opt/sap/config
COPY --chown=sybase --from=installer /opt/sap/collate /opt/sap/collate
ADD entrypoint.sh /opt/sap/
RUN chmod +x /opt/sap/entrypoint.sh \
    && mkdir -p /docker-entrypoint-initdb.d \
    && touch /opt/sap/interfaces \
    && chown -R sybase:sybase /opt/sap /docker-entrypoint-initdb.d
EXPOSE 5000
HEALTHCHECK --interval=15s --timeout=10s --start-period=180s --retries=20 \
    CMD bash -c 'pgrep -f "dataserver.*-s" >/dev/null && source /opt/sap/SYBASE.sh && printf "SELECT 1\nGO\n" | isql -S "${ASE_DS_NAME:-MYSYBASE}" -Usa -P "${ASE_SA_PASSWORD}" -b -w 10 >/dev/null 2>&1' || exit 1
ENTRYPOINT ["/usr/local/bin/tini", "--"]
CMD ["/bin/bash", "/opt/sap/entrypoint.sh"]
