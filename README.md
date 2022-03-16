# SDR Deployment Tools

This is a central place for deploying applications in the Infrastructure team portfolio, primarily but not exclusively related to the Stanford Digital Repository (SDR). This allows all applications to be deployed together with a single set of tools.

## Usage

Make sure that:

* You are on VPN.
* You have `kinit`-ed.
* You have added the public SSH key, often `~/.ssh/id_rsa.pub`, from your machine to [GitHub](https://github.com/settings/keys)
* You have previously `ssh`-ed into all servers.
  * NOTE: If you are unsure about this, run `bin/sdr check_ssh -e [qa|stage|prod]` and watch the output for any errors!
* NOTE: if you run `bin/sdr check_cocina`, you may need to ensure that you have the contribsys gem credentials available for google-books to install the sidekiq-pro gem locally (the credential is already on our deploy target VMs).
  * You can get the env variable name and value from the README in shared_configs for google-books-prod (not in google-books-stage or -qa)
* NOTE: You *may* invoke the `bin/` scripts via `bundle exec`.

### Check your SSH connection to all servers

```
Usage:
  bin/sdr check_ssh -e, --environment=ENVIRONMENT

Options:
      [--only=one two three]               # Update only these repos
      [--except=one two three]             # Update all except these repos
  -s, [--skip-update], [--no-skip-update]  # Skip update repos
  -e, --environment=ENVIRONMENT            # Environment (["qa", "prod", "stage"])
                                           # Possible values: qa, prod, stage

check SSH connections

Example:
  bin/sdr check_ssh -e qa --except sul-dlss/technical-metadata-service sul-dlss/argo
```

NOTE: Watch the output for any errors

### Check versions of cocina-models

```shell
bin/sdr check_cocina
```

This will let you know which versions of cocina-models each project is locked to.


### Run the deploys

```
Usage:
  bin/sdr deploy -e, --environment=ENVIRONMENT

Options:
      [--only=one two three]               # Update only these repos
      [--except=one two three]             # Update all except these repos
  -c, [--cocina], [--no-cocina]            # Only update repos affected by new cocina-models gem release
  -t, [--tag=TAG]                          # Deploy the given tag instead of the main branch
  -s, [--skip-update], [--no-skip-update]  # Skip update repos
  -e, --environment=ENVIRONMENT            # Environment (["qa", "prod", "stage"])
                                           # Possible values: qa, prod, stage

deploy all the services in an environment

Example:
  bin/sdr deploy -s -e qa --only sul-dlss/technical-metadata-service sul-dlss/argo
```

### Create repository tags

```
Usage:
  bin/sdr tag TAG_NAME

Options:
  -m, [--message=TAG MESSAGE]           # Message to describe a newly created tag
  -d, [--delete=DELETE], [--no-delete]  # Delete the tag locally and remotely

create or delete a tag named TAG_NAME

Example:
  bin/sdr tag -m 'coordinating the release of cocina-models 1.2.3' rel-88
```

### A note about ruby versions

As of Jan 2022, some projects have not yet been updated to be Ruby 3.0 compatible, so you either need to deploy all using ruby 2.7 or split the deployment into two chunks:

In Ruby 3.0

```
bin/sdr deploy -e stage --except sul-dlss/dor-services-app
```

Then in Ruby 2.7
```
bin/sdr deploy -e stage --only sul-dlss/dor-services-app
```

The projects that still use ruby 2.7 should eventually be converted to Ruby 3.0

### Only Deploy Repos Related to Cocina-Models Update

Note: this includes dor-services-app and sdr-api in addition to cocina level2 updates.

Use the `--cocina` or `-c` flag.

In Ruby 3.0

```
# -e can be qa or stage or prod
bin/sdr deploy -e stage -c --except sul-dlss/dor-services-app
```

Then in Ruby 2.7
```
# -e can be qa or stage or prod
bin/sdr deploy -e stage -c --only sul-dlss/dor-services-app
```

### Notes and tips:
* All repos will be cloned to `tmp/repos`.
* Any repos cloned to `tmp/repos` that are removed from `config/settings.yml`, *e.g.* projects that have been decommissioned, will be automatically removed from `tmp/repos` the next time any of the sdr-depoy commands are run (unless the repo update is explicitly skipped via user-provided flag).
* If you prefer your output in color, this will work:
```
export SSHKIT_COLOR='TRUE'
```
