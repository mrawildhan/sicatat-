{{flutter_js}}
{{flutter_build_config}}

// Cloudflare may retain the stable main.dart.js URL in a browser cache. Read
// the generated version manifest without caching, then give the entrypoint a
// versioned URL so a newly published SICATAT bundle is loaded immediately.
(async function loadSicatat() {
  try {
    const response = await fetch(`version.json?t=${Date.now()}`, {
      cache: 'no-store',
    });
    const manifest = await response.json();
    const version = manifest.version || Date.now().toString();
    _flutter.buildConfig.builds = _flutter.buildConfig.builds.map((build) =>
      build.mainJsPath
        ? {...build, mainJsPath: `${build.mainJsPath}?v=${version}`}
        : build,
    );
  } catch (_) {
    // The standard entrypoint remains available if the manifest cannot load.
  }

  _flutter.loader.load({
    serviceWorkerSettings: {
      serviceWorkerVersion: {{flutter_service_worker_version}}
    }
  });
})();
