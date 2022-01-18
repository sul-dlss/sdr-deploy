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
bin/check_ssh -e qa # or stage or prod

# Add -s flag to skip the local repo update
bin/check_ssh -s -e qa

# Add --only flag to only check one or more named repos
bin/check_ssh -e qa --only sul-dlss/technical-metadata-service sul-dlss/argo

# Add --except flag to check all but one or more named repos
bin/check_ssh -e qa --except sul-dlss/technical-metadata-service sul-dlss/argo
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

# Add -s flag to skip the local repo update
bin/deploy -s -e qa

# Add --only flag to only deploy one or more named repos
bin/deploy -e qa --only sul-dlss/technical-metadata-service sul-dlss/argo

# Add --except flag to deploy all but one or more named repos
bin/deploy -e qa --except sul-dlss/technical-metadata-service sul-dlss/argo
```

### A note about ruby versions

As of Jan 2022, some projects have not yet been updated to be Ruby 3.0 compatible, so you either need to deploy all using ruby 2.7 or split the deployment into two chunks:

In Ruby 3.0

```
bin/deploy -e stage --except sul-dlss/dor-services-app sul-dlss/ksr-app
```

Then in Ruby 2.7
```
bin/deploy -e stage --only sul-dlss/dor-services-app sul-dlss/ksr-app
```

The 4 projects that still use ruby 2.7 should eventually be converted to Ruby 3.0

### Only Deploy Repos Related to Cocina-Models Update

Note: this includes dor-services-app and sdr-api in addition to cocina level2 updates.

Use the `--cocina` or `-c` flag.

In Ruby 3.0

```
# -e can be qa or stage or prod
bin/deploy -e stage -c --except sul-dlss/dor-services-app
```

Then in Ruby 2.7
```
# -e can be qa or stage or prod
bin/deploy -e stage -c --only sul-dlss/dor-services-app
```

### Notes and tips:
* All repos will be cloned to `tmp/repos`.
* Any repos cloned to `tmp/repos` that are removed from `config/settings.yml`, *e.g.* projects that have been decommissioned, will be automatically removed from `tmp/repos` the next time any of the sdr-depoy commands are run (unless the repo update is explicitly skipped via user-provided flag).
* If you prefer your output in color, this will work:
```
export SSHKIT_COLOR='TRUE'
```
