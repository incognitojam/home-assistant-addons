# Run with: ruby .github/tests/publish-gates_test.rb
# Executes workflow shell steps with synthetic registry/Docker responses.
# Use actionlint/workflow review for expressions and dependencies; scheduling is not simulated.
require 'json'
require 'minitest/autorun'
require 'open3'
require 'yaml'

class PublishGatesTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  BUILD, VALIDATE, PUBLISH = %w[build validate-addon publish-addon].map do |name|
    YAML.load_file(File.join(ROOT, ".github/workflows/#{name}.yml")).fetch('jobs')
  end
  REGISTRY_STUB = <<~BASH
    function .github/scripts/ghcr-tag-state.sh() {
      echo "registry:$1:$2" >&2
      case "$1" in
        *-claude-terminal) state="$CLAUDE_STATE" ;;
        *-codex-terminal) state="$CODEX_STATE" ;;
      esac
      [[ "$state" != error ]] || return 1
      echo "$state"
    }
  BASH

  def shell(script, env, stub = '')
    Open3.capture3(env, 'bash', '-e', '-o', 'pipefail', '-c', stub + script, chdir: ROOT)
  end

  def test_validation_and_required_ci_shell_gates
    [[VALIDATE, 'validation', %w[build hadolint]], [BUILD, 'ci', %w[check claude codex]]].each do |jobs, job, dependencies|
      script = jobs.fetch(job).fetch('steps').last.fetch('run')
      needs = dependencies.to_h { |id| [id, { 'result' => 'success' }] }
      assert shell(script, { 'NEEDS' => JSON.generate(needs) }).last.success?, job
      dependencies.each do |id|
        %w[failure cancelled skipped].each do |state|
          incomplete = needs.merge(id => { 'result' => state })
          refute shell(script, { 'NEEDS' => JSON.generate(incomplete) }).last.success?, "#{job}: #{id} #{state}"
        end
      end
    end
  end

  def test_publish_dependencies_exclude_sibling_validation
    %w[claude codex].each do |addon|
      assert_equal ['check', addon], BUILD.fetch("publish_#{addon}").fetch('needs')
    end
    assert_equal %w[check claude codex], BUILD.fetch('ci').fetch('needs')
    assert_equal %w[build hadolint], VALIDATE.fetch('validation').fetch('needs')
    assert_equal %w[amd64 aarch64], VALIDATE.dig('build', 'strategy', 'matrix', 'arch')
    assert_equal false, VALIDATE.dig('build', 'strategy', 'fail-fast')
  end

  def test_discovery_separates_missing_tags_and_aborts_on_registry_errors
    script = BUILD.fetch('check').fetch('steps').find { |step| step['id'] == 'check' }.fetch('run')
    [['missing', 'present'], ['present', 'missing'], ['error', 'missing'], ['missing', 'error']].each do |claude, codex|
      env = { 'CLAUDE_STATE' => claude, 'CODEX_STATE' => codex,
              'IMAGE_OWNER' => 'example', 'GITHUB_OUTPUT' => '/dev/stdout' }
      out, err, status = shell(script, env, REGISTRY_STUB)
      if [claude, codex].include?('error')
        refute status.success?, err
        refute_match(/^(claude_targets|codex_targets|keys)=/, out)
        next
      end
      assert status.success?, err
      outputs = out.lines.filter_map do |line|
        key, value = line.strip.split('=', 2)
        [key, JSON.parse(value)] if %w[claude_targets codex_targets keys].include?(key)
      end.to_h
      %w[claude codex].zip([claude, codex]).each do |addon, state|
        expected = state == 'missing' ? [["#{addon}-terminal", 'amd64'], ["#{addon}-terminal", 'aarch64']] : []
        assert_equal expected, outputs.fetch("#{addon}_targets").map { |target| target.values_at('addon', 'arch') }
      end
      missing = claude == 'missing' ? 'claude' : 'codex'
      assert_equal ["#{missing}-terminal/amd64", "#{missing}-terminal/aarch64"], outputs.fetch('keys')
    end
  end

  def test_push_rechecks_tag_and_only_loads_tested_archive_when_missing
    script = PUBLISH.fetch('publish').fetch('steps').find { |step| step['name'] == 'Push image' }.fetch('run')
    script = script.gsub('${{ matrix.arch }}', 'amd64').gsub('${{ matrix.addon }}', 'claude-terminal')
                   .gsub('${{ matrix.version }}', '9.9.9')
    image = 'ghcr.io/example/amd64-claude-terminal:9.9.9'
    %w[missing present error].each do |state|
      env = { 'CLAUDE_STATE' => state, 'IMAGE_OWNER' => 'example', 'IMAGE' => image,
              'GITHUB_STEP_SUMMARY' => '/dev/null' }
      out, err, status = shell(script, env, REGISTRY_STUB + 'docker() { echo "docker:$*"; }' + "\n")
      assert_includes err, 'registry:example/amd64-claude-terminal:9.9.9'
      assert_equal state != 'error', status.success?, err
      commands = out.lines.grep(/^docker:/).map(&:strip)
      if state == 'missing'
        assert_equal [
          'docker:load --input image.tar',
          "docker:image inspect --format Image ID: {{.Id}} local/claude-terminal:amd64",
          "docker:tag local/claude-terminal:amd64 #{image}",
          "docker:push #{image}"
        ], commands
      else
        assert_empty commands
      end
    end
  end
end
