# SDR Deployment Tools

This is a central place for deploying SDR applications (and sul_pub). This allows all applications
to be deployed together with a single set of tools.

## Usage

Make sure that:

* You are on VPN.
* You have `kinit`-ed.
* You have added the public SSH key, often `~/.ssh/id_rsa.pub`, from your machine to [GitHub](https://github.com/settings/keys)
* You have previously `ssh`-ed into all servers.
  * NOTE: If you are unsure about this, run `bin/check_ssh -e [qa|stage|prod]` and watch the output for any errors!
* NOTE: if you run `check_cocina`, you may need to ensure that you have the contribsys gem credentials available for google-books to install the sidekiq-pro gem locally (the credential is already on our deploy target VMs).
  * You can get the env variable name and value from shared_configs for google-books-prod -- it's in the shared_configs README. (And it's not in google-books -stage or -qa branches of shared_configs)
* NOTE: You *may* invoke the `bin/` scripts via `bundle exec`.

### Check your SSH connection to all servers

```
bin/check_ssh -e [qa|stage|prod]
```

NOTE: Watch the output for any errors

### Check versions of cocina-models

```
bin/check_cocina
```

This will let you know which versions of cocina-models each project is locked to.


### Run the deploys

```
bin/deploy -e qa # or stage or prod
```

Note:
* All repos will be cloned to `tmp/repos`.
* To skip a repo, comment it out in `config/settings.yml`.
* If you prefer your output in color, this will work:
```
export SSHKIT_COLOR='TRUE'
```
