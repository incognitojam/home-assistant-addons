# Run with: ruby .github/tests/publish-gates_test.rb
# These exercise the workflow's predicates and shell gates, not GitHub's scheduler.
require 'json'
require 'minitest/autorun'
require 'open3'
require 'yaml'

class PublishGatesTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  BUILD = YAML.load_file(File.join(ROOT, '.github/workflows/build.yml'))
  VALIDATE = YAML.load_file(File.join(ROOT, '.github/workflows/validate-addon.yml'))
  PUBLISH = YAML.load_file(File.join(ROOT, '.github/workflows/publish-addon.yml'))
  STATES = %w[success failure cancelled skipped].freeze

  def context(claude: 'success', codex: 'success', check: 'success',
              event: 'push', ref: 'refs/heads/main', canceled: false,
              claude_targets: '[{"arch":"amd64"}]', codex_targets: '[{"arch":"aarch64"}]')
    {
      'github' => { 'event_name' => event, 'ref' => ref },
      'canceled' => canceled,
      'needs' => {
        'check' => { 'result' => check, 'outputs' => {
          'claude_targets' => claude_targets, 'codex_targets' => codex_targets
        } },
        'claude' => { 'result' => claude }, 'codex' => { 'result' => codex }
      }
    }
  end

  # The publish predicates use boolean operators and scalar context values only.
  # Evaluate the actual YAML conditions so changes to a dependency, status check,
  # event guard or empty-list guard are exercised by the scenarios below.
  def predicate(expression, values)
    expression = expression.gsub('cancelled()', values.fetch('canceled', false).inspect)
    expression = expression.gsub(/(?:github|needs|inputs)\.[a-zA-Z_.]+/) do |path|
      values.dig(*path.split('.')).to_s.inspect
    end
    eval(expression) # Trusted repository workflow expressions, not external input.
  end

  def publications(values)
    %w[claude codex].select do |addon|
      predicate(BUILD.fetch('jobs').fetch("publish_#{addon}").fetch('if'), values)
    end
  end

  def gate(workflow, job, needs)
    script = workflow.fetch('jobs').fetch(job).fetch('steps').last.fetch('run')
    _out, _err, status = Open3.capture3({ 'NEEDS' => JSON.generate(needs) }, 'bash', '-e', '-c', script)
    status.success?
  end

  def test_both_healthy_and_sibling_failures_or_cancellations
    assert_equal %w[claude codex], publications(context)
    %w[failure cancelled skipped].each do |state|
      assert_equal ['codex'], publications(context(claude: state)), state
      assert_equal ['claude'], publications(context(codex: state)), state
    end
  end

  def test_one_own_architecture_or_lint_failure_blocks_own_release
    # With fail-fast disabled, a matrix succeeds only if every architecture succeeds.
    STATES.repeated_permutation(2) do |arches|
      build_result = arches.all? { |state| state == 'success' } ? 'success' : 'failure'
      STATES.each do |lint|
        needs = { 'build' => { 'result' => build_result }, 'hadolint' => { 'result' => lint } }
        healthy = arches == %w[success success] && lint == 'success'
        assert_equal healthy, gate(VALIDATE, 'validation', needs), "#{arches} / lint #{lint}"
        own_result = healthy ? 'success' : 'failure'
        assert_equal(healthy ? %w[claude codex] : ['codex'], publications(context(claude: own_result)))
        assert_equal(healthy ? %w[claude codex] : ['claude'], publications(context(codex: own_result)))
      end
    end
    %w[cancelled skipped].each do |state|
      refute gate(VALIDATE, 'validation', { 'build' => { 'result' => state }, 'hadolint' => { 'result' => 'success' } })
    end
  end

  def test_check_failure_or_missing_outputs_never_publish
    %w[failure cancelled skipped].each do |state|
      assert_empty publications(context(check: state, claude_targets: '', codex_targets: ''))
    end
    assert_empty publications(context(claude_targets: '', codex_targets: ''))
  end

  def test_whole_run_cancellation_pr_and_non_main_never_publish
    assert_empty publications(context(canceled: true))
    values = context(canceled: true).merge('inputs' => { 'targets' => '[{"arch":"amd64"}]' })
    refute predicate(PUBLISH.fetch('jobs').fetch('publish').fetch('if'), values)
    assert_empty publications(context(event: 'pull_request'))
    assert_empty publications(context(event: 'workflow_dispatch', ref: 'refs/heads/proposal'))
    assert_equal %w[claude codex], publications(context(event: 'workflow_dispatch'))
  end

  def test_no_tags_skips_publish_before_dynamic_matrix
    assert_empty publications(context(claude_targets: '[]', codex_targets: '[]'))
    assert_equal ['codex'], publications(context(claude_targets: '[]'))
    assert_equal ['claude'], publications(context(codex_targets: '[]'))
    ['', '[]'].each do |targets|
      values = context.merge('inputs' => { 'targets' => targets })
      refute predicate(PUBLISH.fetch('jobs').fetch('publish').fetch('if'), values)
    end
  end

  def test_required_ci_rejects_any_incomplete_validation
    STATES.repeated_permutation(3) do |states|
      needs = %w[check claude codex].zip(states).to_h.transform_values { |state| { 'result' => state } }
      assert_equal states.all? { |state| state == 'success' }, gate(BUILD, 'ci', needs), states.inspect
    end
  end

  def test_tag_discovery_separates_addons_and_fails_closed
    script = BUILD.fetch('jobs').fetch('check').fetch('steps').find { |step| step['id'] == 'check' }.fetch('run')
    stub = <<~BASH
      function .github/scripts/ghcr-tag-state.sh() {
        case "$1" in
          */*-claude-terminal) state="$CLAUDE_STATE" ;;
          */*-codex-terminal) state="$CODEX_STATE" ;;
        esac
        [[ "$state" != error ]] || return 1
        echo "$state"
      }
    BASH
    %w[present missing].repeated_permutation(2) do |claude, codex|
      env = { 'CLAUDE_STATE' => claude, 'CODEX_STATE' => codex,
              'IMAGE_OWNER' => 'example', 'GITHUB_OUTPUT' => '/dev/stdout' }
      out, err, status = Open3.capture3(env, 'bash', '-e', '-c', stub + script, chdir: ROOT)
      assert status.success?, err
      outputs = out.lines.filter_map do |line|
        key, value = line.strip.split('=', 2)
        [key, JSON.parse(value)] if %w[claude_targets codex_targets keys].include?(key)
      end.to_h
      %w[claude codex].zip([claude, codex]).each do |addon, state|
        targets = outputs.fetch("#{addon}_targets")
        assert_equal(state == 'missing' ? 2 : 0, targets.size)
        assert targets.all? { |target| target['addon'] == "#{addon}-terminal" }
        assert_equal %w[amd64 aarch64], targets.map { |target| target['arch'] } if state == 'missing'
      end
      assert_equal outputs.fetch('claude_targets').size + outputs.fetch('codex_targets').size, outputs.fetch('keys').size
    end
    %w[claude codex].each do |addon|
      env = { 'CLAUDE_STATE' => 'missing', 'CODEX_STATE' => 'missing',
              'IMAGE_OWNER' => 'example', 'GITHUB_OUTPUT' => '/dev/stdout' }
      env["#{addon.upcase}_STATE"] = 'error'
      out, _err, status = Open3.capture3(env, 'bash', '-e', '-c', stub + script, chdir: ROOT)
      refute status.success?
      refute_match(/^(claude_targets|codex_targets|keys)=/, out)
    end
  end

  def test_publish_loads_tested_artifact_and_rechecks_immutable_tag
    script = PUBLISH.fetch('jobs').fetch('publish').fetch('steps').find { |step| step['name'] == 'Push image' }.fetch('run')
    script = script.gsub('${{ matrix.arch }}', 'amd64').gsub('${{ matrix.addon }}', 'example-addon')
                   .gsub('${{ matrix.version }}', '9.9.9')
    stub = <<~BASH
      function .github/scripts/ghcr-tag-state.sh() {
        echo "registry-check:$1:$2" >&2
        [[ "$REGISTRY_STATE" != error ]] || return 1
        echo "$REGISTRY_STATE"
      }
      docker() { echo "docker:$*"; }
    BASH
    %w[present missing error].each do |state|
      env = { 'REGISTRY_STATE' => state, 'IMAGE_OWNER' => 'example',
              'IMAGE' => 'ghcr.io/example/amd64-example-addon:9.9.9',
              'GITHUB_STEP_SUMMARY' => '/dev/null' }
      out, err, status = Open3.capture3(env, 'bash', '-e', '-c', stub + script)
      assert_includes err, 'registry-check:example/amd64-example-addon:9.9.9'
      if state == 'missing'
        assert status.success?
        assert_includes out, 'docker:load --input image.tar'
        assert_includes out, 'docker:tag local/example-addon:amd64 ghcr.io/example/amd64-example-addon:9.9.9'
        assert_includes out, 'docker:push ghcr.io/example/amd64-example-addon:9.9.9'
        refute_includes out, 'docker:build'
      else
        assert_equal state == 'present', status.success?
        refute_includes out, 'docker:'
      end
    end
  end

  def test_dependency_and_permission_contracts
    jobs = BUILD.fetch('jobs')
    assert_equal %w[check claude codex], jobs.fetch('ci').fetch('needs')
    assert_equal 'CI', jobs.fetch('ci').fetch('name')
    assert_equal 'ubuntu-slim', jobs.fetch('ci').fetch('runs-on')
    assert_equal 'always()', jobs.fetch('ci').fetch('if')
    %w[claude codex].each do |addon|
      assert_equal ['check', addon], jobs.fetch("publish_#{addon}").fetch('needs')
      assert_equal 'check', jobs.fetch(addon).fetch('needs')
      assert_equal "#{addon}-terminal", jobs.fetch(addon).fetch('with').fetch('addon')
    end
    assert_equal %w[amd64 aarch64], VALIDATE.dig('jobs', 'build', 'strategy', 'matrix', 'arch')
    assert_equal false, VALIDATE.dig('jobs', 'build', 'strategy', 'fail-fast')
    assert_equal %w[build hadolint], VALIDATE.dig('jobs', 'validation', 'needs')
    assert_equal 'always()', VALIDATE.dig('jobs', 'validation', 'if')
    [BUILD, VALIDATE, PUBLISH].each do |workflow|
      assert_equal({ 'contents' => 'read' }, workflow.fetch('permissions'))
      workflow.fetch('jobs').each do |id, job|
        next unless job.dig('permissions', 'packages') == 'write'
        assert id.start_with?('publish'), id
      end
    end
    assert_equal false, PUBLISH.dig('jobs', 'publish', 'concurrency', 'cancel-in-progress')
    assert_equal 'publish-${{ matrix.addon }}-${{ matrix.arch }}', PUBLISH.dig('jobs', 'publish', 'concurrency', 'group')
    jobs.fetch('check').fetch('outputs').each_value { |value| assert_includes value, "|| '[]'" }
  end
end
