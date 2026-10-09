# klyp/wordpress

WordPress core for Composer, built and published by Klyp.

A scheduled GitHub Action checks wordpress.org every 15 minutes. When there's a new release on **any** branch, it publishes that release here as a Composer version, including security backports such as 6.9.9 while 7.1.x is current. It doesn't wait for a third party to repackage the release.

Every stable release from **4.7** onward is available.

## Using it in a project

```jsonc
{
  "require": {
    "klyp/wordpress": "^7.1"
  },
  "config": {
    "allow-plugins": {
      "klyp/wordpress-core-installer": true
    }
  },
  "extra": {
    "wordpress-install-dir": "wp"
  }
}
```

`klyp/wordpress` has the package type `wordpress-core` and depends on [`klyp/wordpress-core-installer`](https://github.com/klyp/wordpress-core-installer). That Composer plugin installs core into `extra.wordpress-install-dir` (default `wordpress/`) instead of `vendor/`.

### Switching from another WordPress core package

1. In `composer.json`:
   - Replace your current WordPress core package in `require` with `"klyp/wordpress": "^6.9"`, using the same version constraint.
   - Remove the old core installer plugin from `config.allow-plugins`, and add `"klyp/wordpress-core-installer": true`.
   - Leave `extra.wordpress-install-dir` unchanged.
2. Update the new packages together with the ones you're replacing:
   ```sh
   composer update klyp/wordpress klyp/wordpress-core-installer <old-core-package> <old-installer-package> -W
   ```
3. Check that `composer.lock` lists `klyp/wordpress` and `klyp/wordpress-core-installer`, and no other package of type `wordpress-core` or WordPress core installer. Only one installer plugin should handle WordPress core.

Apply the same change to project skeletons such as `3equals/hummingbird-project`, so new sites start on `klyp/wordpress`.

## How it works

- `master` contains only the tooling in this README, `bin/` and `.github/`. Its `composer.json` is a file-less `metapackage` that only gives Packagist the package name. Packagist lists it as `dev-master`, but it installs nothing, and normal constraints such as `^7.1` never select it.
- Each WordPress version is a **tag** (`7.1.2`, `6.9.9`, `4.7.31`, ...). Each tag points to an orphan commit that holds:
  - the unmodified contents of the official `https://wordpress.org/wordpress-X.Y.Z.zip`, checked against its published `.sha1`
  - a generated `composer.json`. Its `php` requirement comes from that release's `$required_php_version`.
- Tags are never rewritten. If a tag already exists on the remote, the build skips it.

| File | Purpose |
| --- | --- |
| [bin/build-release.sh](bin/build-release.sh) | Builds and pushes one version: download, verify sha1, add `composer.json`, tag, push. |
| [bin/sync-releases.sh](bin/sync-releases.sh) | Compares [the WordPress release list](https://api.wordpress.org/core/stable-check/1.0/) with the remote tags, builds what's missing and pushes it. Packagist picks up new tags through its GitHub integration. |
| [.github/workflows/sync.yml](.github/workflows/sync.yml) | Runs the sync every 15 minutes, or on demand. Also commits a monthly keepalive, because GitHub disables schedules after 60 idle days. |
| [.github/workflows/test.yml](.github/workflows/test.yml) | Installs the newest release, and the newest release of the previous branch, from Packagist into a scratch project. |

### Publishing a release immediately

The schedule usually picks up a new release within 15 minutes. To publish one right away:

- **GitHub:** Actions → *Sync WordPress releases* → *Run workflow*. Enter a version such as `7.1.3`, or leave it empty to build everything that's missing.
- **Locally**, with push access:
  ```sh
  bin/build-release.sh 7.1.3
  ```

Other local options:

```sh
DRY_RUN=1 bin/sync-releases.sh          # list versions that aren't published yet
NO_PUSH=1 bin/build-release.sh 6.9.9    # build and tag locally without pushing
```

The scripts require `bash`, `curl`, `jq`, `unzip` and `git`.

## One-time setup

1. The repository must be **public**, so that Packagist can read it.
2. Under Settings → Actions → General → Workflow permissions, choose **Read and write permissions**. The workflow needs this to push tags and the keepalive commit. If `master` has branch protection, allow GitHub Actions to push, or the keepalive fails.
3. On [packagist.org](https://packagist.org/packages/submit), submit `https://github.com/klyp/wordpress` from the Klyp account. Connect the GitHub integration (Profile → Settings → GitHub) so Packagist is notified on every tag push. No Packagist token is stored in this repo.
4. **Protect the tags.** Under Settings → Rules → Rulesets → New tag ruleset, target all tags (`*`) and enable **Restrict updates** and **Restrict deletions**, with no bypass list. The sync never rewrites a tag, and this ruleset stops anyone else (or a leaked token) from replacing a published version with different code. Keep **Restrict creations** off, or the workflow can't publish new tags.
5. After merging to `master`, run *Sync WordPress releases* once to backfill every version from 4.7 up. That's about 480 tags, and the run is safe to repeat if it times out.

## License

WordPress is licensed under the GPLv2 or later. The build tooling in this repository uses the same license.
