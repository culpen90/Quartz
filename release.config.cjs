module.exports = {
  branches: ["main"],
  repositoryUrl: "https://github.com/QuartzBrowser/Quartz.git",
  tagFormat: "v${version}",
  plugins: [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    [
      "@semantic-release/changelog",
      {
        changelogFile: "CHANGELOG.md",
      },
    ],
    [
      "@semantic-release/exec",
      {
        prepareCmd: [
          "printf '%s\\n' '${nextRelease.version}' > version.txt",
          "VERSION='${nextRelease.version}' BUILD_NUMBER='${nextRelease.version}' ZIP_APP=1 Scripts/package-macos-app.sh",
          "mv dist/Quartz.zip dist/Quartz-${nextRelease.gitTag}-macos-universal.zip",
        ].join(" && "),
      },
    ],
    [
      "@semantic-release/git",
      {
        assets: ["CHANGELOG.md", "version.txt"],
        message: "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}",
      },
    ],
    [
      "@semantic-release/github",
      {
        assets: [
          {
            path: "dist/Quartz-${nextRelease.gitTag}-macos-universal.zip",
            label: "Quartz ${nextRelease.gitTag} macOS universal app",
          },
        ],
      },
    ],
  ],
};
