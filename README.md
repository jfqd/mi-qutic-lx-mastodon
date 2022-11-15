# mi-qutic-lx-mastodon

This repository is based on [Joyent mibe](https://github.com/jfqd/mibe).

## description

mastodon lx-brand image

## Build Image

```
cd /opt/mibe/repos
/opt/tools/bin/git clone https://github.com/jfqd/mi-qutic-lx-mastodon.git
LXBASE_IMAGE_UUID=$(imgadm list | grep qutic-lx-base | tail -1 | awk '{ print $1 }')
TEMPLATE_ZONE_UUID=$(vmadm lookup alias='qutic-lx-template-zone')
../bin/build_lx $LXBASE_IMAGE_UUID $TEMPLATE_ZONE_UUID mi-lx-mastodon && \
  imgadm install -m /opt/mibe/images/qutic-lx-mastodon-*-imgapi.dsmanifest \ 
                 -f /opt/mibe/images/qutic-lx-mastodon-*.zfs.gz
```