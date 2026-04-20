# CA Certificates

Place company CA certificate files here when building the CA-aware image.

Files must use the `.crt` extension:

```text
admin/ca/company-root-ca.crt
admin/ca/company-intermediate-ca.crt
```

`admin/build-ca-image.sh` will stop if this directory does not contain any `.crt` files.
