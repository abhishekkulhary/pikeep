import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets.dart';

/// What the app does not do for you: putting databases back, and starting over
/// on a new disk or a new Pi. Kept as copyable commands rather than automated,
/// because a wrong database import is worse than a slow one.
class RestoreGuideScreen extends StatelessWidget {
  const RestoreGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restore guide')),
      body: PageBody(children: [
        const Notice(
          'PiKeep restores files. Each Immich or Nextcloud snapshot also contains a database dump at '
          '/mnt/ssd/backup-staging/<source>-db.sql — restore the files and the dump from the SAME '
          'snapshot, then load the dump with the steps below. Run the commands on the Pi (ssh in, then sudo -i).',
          kind: NoticeKind.info,
        ),
        const _Section(
          title: 'If the SSD died',
          intro: 'Backups stop on their own: the Pi refuses to back up while /mnt/ssd is not mounted, '
              'and nothing on OneDrive is cleaned up. To recover:',
          steps: [
            ('Connect the new disk, format it ext4 and mount it at /mnt/ssd (same fstab entry, new UUID).', null),
            ('Recreate the app folders Docker expects, empty:', 'mkdir -p /mnt/ssd/immich /mnt/ssd/nextcloud'),
            ('In PiKeep: Snapshots → pick the newest snapshot of each source → Restore whole snapshot → '
                'Original location. Do Immich and Nextcloud one after the other.', null),
            ('Then load each database as below, and start the containers.', null),
          ],
        ),
        const _Section(
          title: 'Immich database (PostgreSQL)',
          intro: 'Immich needs an empty database folder for this. From the Immich app folder:',
          steps: [
            ('Stop Immich:', 'cd /mnt/ssd/immich/app && docker compose down'),
            ('Move the old database folder aside (keep it until Immich works again):',
                'mv /mnt/ssd/immich/postgres /mnt/ssd/immich/postgres.old'),
            ('Start only the database:', 'docker compose up -d database'),
            ('Load the dump (the sed line is from Immich\'s own restore guide):',
                "sed \"s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g\" /mnt/ssd/backup-staging/immich-db.sql | docker exec -i immich_postgres psql --dbname=postgres --username=postgres"),
            ('Start everything:', 'docker compose up -d'),
          ],
        ),
        const _Section(
          title: 'Nextcloud database (MariaDB)',
          intro: 'The dump contains every database, so it replaces them all.',
          steps: [
            ('Maintenance mode on:', 'docker exec -u www-data nextcloud_app php occ maintenance:mode --on'),
            ('Load the dump:',
                'docker exec -i nextcloud_db sh -c \'exec mariadb -u root -p"\$MARIADB_ROOT_PASSWORD"\' < /mnt/ssd/backup-staging/nextcloud-db.sql'),
            ('Maintenance mode off, and tell sync clients the data changed:',
                'docker exec -u www-data nextcloud_app php occ maintenance:mode --off && docker exec -u www-data nextcloud_app php occ maintenance:data-fingerprint'),
          ],
        ),
        const _Section(
          title: 'Single files back into Nextcloud',
          intro: 'After restoring files to a separate folder and copying them into a user\'s files folder, '
              'Nextcloud needs to notice them:',
          steps: [
            ('Rescan:', 'docker exec -u www-data nextcloud_app php occ files:scan --all'),
          ],
        ),
        const _Section(
          title: 'A new Pi, or without the app',
          intro: 'All you need is your OneDrive login and the restic password from your password manager.',
          steps: [
            ('Install restic and a current rclone:', 'sudo apt install -y restic && sudo -v ; curl https://rclone.org/install.sh | sudo bash'),
            ('Connect OneDrive as the remote "onedrive":', 'sudo rclone config'),
            ('Put the password back:', "sudo sh -c 'umask 077; cat > /root/.restic-pass'"),
            ('Then install the PiKeep agent and use the app — or restic directly:',
                'sudo RESTIC_PASSWORD_FILE=/root/.restic-pass restic -r rclone:onedrive:pi-backup snapshots'),
          ],
        ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.intro, required this.steps});
  final String title;
  final String intro;
  final List<(String, String?)> steps;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SectionCard(title: title, padding: const EdgeInsets.fromLTRB(0, 8, 0, 12), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(intro, style: Theme.of(context).textTheme.bodyMedium),
      ),
      for (final (i, (text, cmd)) in steps.indexed)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: cs.primaryContainer,
              child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text),
                if (cmd != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: SelectableText(cmd,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4)),
                      ),
                      IconButton(
                        tooltip: 'Copy',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: cmd));
                          showSnack(context, 'Command copied');
                        },
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          ]),
        ),
    ]);
  }
}
