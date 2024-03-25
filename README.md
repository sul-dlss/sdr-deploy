# SDR Deployment Tools

This is a central place for deploying applications in the Infrastructure team portfolio, primarily but not exclusively related to the Stanford Digital Repository (SDR). This allows all applications to be deployed together with a single set of tools.

## Requirements

sdr-deploy expects Ruby 3.2.

## Usage

Make sure that:

* You are on VPN.
* You have `kinit`-ed.
* You have added the public SSH key, often `~/.ssh/id_rsa.pub` or `~/.ssh/id_ed25519.pub`, from your machine to [GitHub](https://github.com/settings/keys)
* You have properly configured your local SSH setup to work with `sdr-infra.stanford.edu`
* You have logged into `sdr-infra.stanford.edu` and cloned this repository.
* You have previously `ssh`-ed into all servers.
  * NOTE: If you are unsure about this, run `bin/sdr check_ssh -e [qa|stage|prod]` and watch the output for any errors!
* NOTE: if you run `bin/sdr check_cocina`, you may need to ensure that you have the contribsys gem credentials available for google-books to install the sidekiq-pro gem locally (the credential is already on our deploy target VMs).
  * You can get the env variable name and value from the README in shared_configs for google-books-prod (not in google-books-stage or -qa)
* NOTE: You *may* invoke the `bin/` scripts via `bundle exec`.

### SSH Setup

Follow the [Github Documentation](https://docs.github.com/en/authentication/connecting-to-github-with-ssh) if you need to establish new ssh keys.

#### Local SSH Config

1.) Edit your local `~/.ssh/config` file to look like:

```
## Uncomment these so you can SSH to boxes without the full .stanford.edu domain name
##   e.g., type `ssh sdr-infra` and the SSH client will use `*.stanford.edu` config
# CanonicalizeHostname yes
# CanonicalDomains stanford.edu

Host *.stanford.edu
    # Forward your SSH key so you can interact with GitHub
    ForwardAgent yes
    # Set up Kerberos authentication
    GSSAPIAuthentication yes
    GSSAPIDelegateCredentials yes
    # Specify your Stanford username here
    User <SUNETID without @stanford.edu>
```

Note that order matters in `config` so place this before (or comment out) `Host *` configuration.

2.) Add your github key to your local ssh agent

```
# Or whatever the path is to the private key you've added to GitHub
ssh-add ~/.ssh/id_ed25519
```

3.) Verify the correct key(s) are forwarded to sdr-infra

Verify the results of `ssh-add -L` on both your laptop and `sdr-infra` match.

You can also try this on both your laptop and the server and verify you get the response shown.  If not, then your local SSH key or forwarding may not be setup correctly.

See https://docs.github.com/en/authentication/connecting-to-github-with-ssh/using-ssh-agent-forwarding for more information

```
ssh -T git@github.com

Hi [GITHUB_USERNAME]! You've successfully authenticated, but GitHub does not provide shell access.
```

### Connecting to sdr-infra.stanford.edu

With the above configuration, you will need to connect to `sdr-infra.stanford.edu` via ssh and will be presented with a MFA challenge:

```
ssh sdr-infra.stanford.edu
(SUNETID@sdr-infra.stanford.edu) Duo two-factor login for SUNETID

Enter a passcode or select one of the following options:

 1. Duo Push to XXX-XXX-1234
 2. Phone call to XXX-XXX-1234
 3. SMS passcodes to XXX-XXX-1234

Passcode or option (1-3):
```

Once connected, you can proceed.

### Configure bundler for your local path

Set the bundler path:
```
bundle config --global path /home/[username]/.vendor/bundle
```

Setup contribsys gem authentication (Sidekiq pro):
```
bundle config gems.contribsys.com USER:PASS
```

If already setup on your laptop, you can get the value for USER:PASS needed above:

```
# on your laptop, it should show the USER:PASS values
echo $BUNDLE_GEMS__CONTRIBSYS__COM
user123:pass678
```

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
  bin/sdr check_ssh -s -e qa --except sul-dlss/technical-metadata-service sul-dlss/argo
```

NOTE: Watch the output for any errors

### Check versions of cocina-models

```
Usage:
  bin/sdr check_cocina

Options:
  -s, [--skip-update], [--no-skip-update]  # Skip update repos
  -t, --branch, [--tag=TAG]                # Check cocina version in the given tag or branch instead of the default branch

check for cocina-models version mismatches

Example:
  bin/sdr check_cocina -s -t rel-2022-08-01
  bin/sdr check_cocina -t my-wip-branch
```

This will let you know which versions of cocina-models are used by each project with it in Gemfile.lock.

### Create repository tags

This command tags repositories in parallel.

**NOTE**: We conventionally name tags `rel-{YYYY}-{MM}-{DD}`.

```
Usage:
  bin/sdr tag TAG_NAME

Options:
  -m, [--message=TAG MESSAGE]           # Message to describe a newly created tag
  -d, [--delete=DELETE], [--no-delete]  # Delete the tag locally and remotely
  -c, [--cocina], [--no-cocina]         # Only update repos affected by new cocina-models gem release

create or delete a tag named TAG_NAME

Examples:
  bin/sdr tag -m 'coordinating the deploy of dependency updates' rel-2022-09-05
  bin/sdr tag -c -m 'coordinating the release of cocina-models 0.66.6' rel-2022-09-14
```

### Run the deploys

This command deploys repositories in parallel.

```
Usage:
  bin/sdr deploy -e, --environment=ENVIRONMENT

Options:
      [--only=one two three]               # Update only these repos
      [--except=one two three]             # Update all except these repos
  -c, [--cocina], [--no-cocina]            # Only update repos affected by new cocina-models gem release
  -b, [--before-command=BEFORE_COMMAND]    # Run this command on each host before deploying
  -t, --branch, [--tag=TAG]                # Deploy the given tag or branch instead of the default branch
  -s, [--skip-update], [--no-skip-update]  # Skip update repos
  -e, --environment=ENVIRONMENT            # Deployment environment
                                           # Possible values: qa, prod, stage

deploy all the services in an environment

Examples:
  bin/sdr deploy -s -e qa -t my-wip-branch --only=sul-dlss/technical-metadata-service
  bin/sdr deploy -c -e qa -t rel-2022-09-14
```

**NOTE 0**:

As part of the deployment process, the cocina-models versions used by the apps being deployed will be checked. If all apps use the same version, the deploy will proceed. If there is divergence at the major- or minor-level, the deploy will be halted. If there is divergence at the patch-level, the user will be notified about the different versions used and then prompted to continue (defaulting to "yes").

**NOTE 1**:

If **`io-wait`** or **`strscan`** gems update, you _may_ need to ssh to the VM and manually run `gem install io-wait` and/or `gem install strscan` to keep the deployed app from breaking.

Why? Because `io-wait` and `strscan` are "system" gems, and aren't managed by bundler.

dlss-capistrano now automagically updates `strscan`;  see https://github.com/sul-dlss/dlss-capistrano/blob/main/lib/dlss/capistrano/tasks/strscan.rake

If there is a problem, you can use `SKIP_UPDATE_STRSCAN` env var for an individual deploy (also for all deploys?):

    ```
    cd yer_local_cloned_argo directory
    SKIP_UPDATE_STRSCAN=true cap deploy stage
    ```

You can update a gem for all apps for a given environment, like this:

    ```
    bin/sdr deploy -e stage -b 'gem install io-wait'
    ```

Or you can update a gem for a specific app like this:

    ```
    cd yer_local_cloned_argo directory
    cap stage remote_execute['gem install io-wait']
    ```

**NOTE 2**: We have a couple applications that use environments outside of our standard ones (qa, prod, and stage), and sdr-deploy deploys to these oddball environments when deploying to prod. These are configured on a per-application basis in `config/settings.yml` via, e.g.:

```yaml
  - name: sul-dlss/sul_pub
    non_standard_envs:
      - uat
  - name: sul-dlss/technical-metadata-service
    non_standard_envs:
      - retro
```

**NOTE 3**: Sometimes we want to be extra careful when deploying certain apps to certain environments. These are configured on a per-application basis in `config/settings.yml` via, e.g.:

```yaml
  - name: sul-dlss/argo
    confirmation_required_envs:
      - prod
```

**NOTE 4**: Sometimes we want to skip deploying to certain environments. These are configured on a per-application basis in `config/settings.yml` via, e.g.:

```yaml
  - name: sul-dlss/happy-heron
    skip_envs:
      - prod
```

### Only Deploy Repos Related to Cocina-Models Update

Note: this includes dor-services-app and sdr-api in addition to cocina level2 updates.

**[Turn off Google Books](https://sul-gbooks-prod.stanford.edu/features) when deploying to production.** This avoids failed deposit due to a temporary Cocina model mismatch. Unlike other applications, the deposits will fail without retry and require manual remediation.

Use the `--cocina` or `-c` flag.

Then

```
# -e can be qa or stage or prod
bin/sdr deploy -e stage -c
```

### Notes and tips:
* All repos will be cloned to `tmp/repos`.
* Any repos cloned to `tmp/repos` that are removed from `config/settings.yml`, *e.g.* projects that have been decommissioned, will be automatically removed from `tmp/repos` the next time any of the sdr-deploy commands are run (unless the repo update is explicitly skipped via user-provided flag).
* If you prefer your output in color, this will work:
```
export SSHKIT_COLOR='TRUE'
```
