/// Route annotation emitted by flxc for @page("/route") in .flx files.
/// Roadmap: a build step collects these into a generated router table.
class page {
  const page(this.path);
  final String path;
}
