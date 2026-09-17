{{flutter_js}}
{{flutter_build_config}}

// Browsers may keep main.dart.js in cache. Flutter fills the service-worker
// version with a hash of this build's files, so it changes on every deploy
// that changes the code, even when the app version number stays the same.
// Using it in the entrypoint URL makes a new bundle load immediately.
(function loadSicatat() {
  const buildHash = {{flutter_service_worker_version}};
  _flutter.buildConfig.builds = _flutter.buildConfig.builds.map((build) =>
    build.mainJsPath
      ? {...build, mainJsPath: `${build.mainJsPath}?v=${buildHash}`}
      : build,
  );

  _flutter.loader.load({
    serviceWorkerSettings: {
      serviceWorkerVersion: buildHash,
    },
  });
})();
