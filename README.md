# Pyre Lib

The pyre library.

> For a fully configured standlone Pyre Application see [Pyre App](https://github.com/chrislaskey/pyre_app)

## Pyre

Core multi-agent LLM library for [Pyre](https://github.com/chrislaskey/pyre).

Pyre orchestrates specialized LLM workflows for software development.

Orchestration layer runs on [Jido](https://jido.run/). Each agent is a reusable
[Jido Action](https://hexdocs.pm/jido_action/Jido.Action.html) with a persona
that guides its output. The pipeline includes a review loop that iterates until
the code reviewer approves.

### Installation

Add `pyre` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pyre, git: "https://github.com/chrislaskey/pyre_lib", branch: "main"}
  ]
end
```

Then run the installer to copy persona files and set up the runs directory:

```bash
mix deps.get
mix pyre.install
```

This creates:

- `priv/pyre/personas/` — Editable persona files for each agent
- `priv/pyre/features/.gitkeep` — Directory where pipeline artifacts are stored
- `.gitignore` entries to exclude run output from version control

### Configuration

#### PubSub

Pyre can emit pubsub events when lifecycle events occur. This is optional if
you're only calling `pyre` on the command line and are not integrating it more
deeply within your app.

To enable PubSub events update `config/config.exs`:

```elixir
# config/config.exs
config :pyre, :pubsub, MyApp.PubSub
```

Replace `MyApp.PubSub` with the PubSub server already started in your application's
supervision tree.

**Note**: This is required if you are using the [PyreWeb](https://github.com/chrislaskey/pyre_lib) web interface, since the UI listens for these events.

#### Allowed Paths

By default, agent file tools (read, write, list directory) are sandboxed to
the working directory. If you need access to sibling apps
or shared libraries, you can allow additional directories.

**Environment variable** (comma-separated):

```bash
export PYRE_ALLOWED_PATHS="/path/to/apps/other,/path/to/libs/shared"
```

**Application config:**

```elixir
# config/runtime.exs
if paths = System.get_env("PYRE_ALLOWED_PATHS") do
  config :pyre,
    allowed_paths:
      paths
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&Path.expand/1)
end
```

**Flow option** (programmatic):

```elixir
Pyre.Flows.FeatureBuild.run("Build a feature",
  project_dir: "apps/tools",
  allowed_paths: ["/path/to/apps/other"]
)
```

Relative paths are resolved against the working directory (`--project-dir`),
so `../other` with `--project-dir apps/tools` resolves to `apps/other`. The
working directory itself is always included automatically.

#### Lifecycle hooks

Pyre dispatches lifecycle events (flow start/complete, action start/complete,
LLM call complete) to a configurable callback module. Create a module that
`use Pyre.Config` and override the callbacks you need:

```elixir
defmodule MyApp.Pyre.Config do
  use Pyre.Config

  @impl true
  def after_flow_complete(%Pyre.Events.FlowCompleted{} = event) do
    MyApp.Telemetry.emit(:pyre_flow_complete, %{
      flow: event.flow_module,
      elapsed_ms: event.elapsed_ms
    })
    :ok
  end
end
```

Then register it in your config:

```elixir
# config/config.exs
config :pyre, config: MyApp.Pyre.Config
```

Any callback not overridden returns `:ok` by default. Exceptions in callbacks
are rescued and logged — they never crash the running flow.

#### GitHub integration

##### Personal access token (Shipper agent)

To enable the Shipper agent (creates branches and opens GitHub PRs), configure
your repository in `config/runtime.exs`:

```elixir
# config/runtime.exs
if System.get_env("PYRE_GITHUB_REPO_URL") do
  config :pyre, :github,
    repositories: [
      [
        url: System.get_env("PYRE_GITHUB_REPO_URL"),
        token: System.get_env("PYRE_GITHUB_TOKEN"),
        base_branch: System.get_env("PYRE_GITHUB_BASE_BRANCH", "main")
      ],
      # [
      #   url: System.get_env("ADDITIONAL_GITHUB_REPO_URL"),
      #   token: System.get_env("ADDITIONAL_GITHUB_TOKEN"),
      #   base_branch: System.get_env("ADDITIONAL_GITHUB_BASE_BRANCH", "main")
      # ]
    ]
end
```

Set the required environment variables:

```bash
export PYRE_GITHUB_TOKEN=ghp_...
export PYRE_GITHUB_REPO_URL=https://github.com/myorg/my-app
```

The Shipper automatically picks up the first configured repository. To target a
specific repo at runtime, pass the `:github` option:

```elixir
Pyre.Flows.FeatureBuild.run("Build a feature",
  github: %{owner: "acme", repo: "app", token: token, base_branch: "main"}
)
```

##### GitHub App (webhook-triggered PR reviews)

Pyre also supports a GitHub App integration for `@mention`-triggered PR reviews.
The webhook handling, mention parsing, and job queue live in
[PyreWeb](https://github.com/chrislaskey/pyre_lib). The core review workflow
(`Pyre.RemoteReview`) and GitHub API infrastructure (`Pyre.GitHub.App`) remain
in pyre_core. See the
[PyreWeb README](https://github.com/chrislaskey/pyre_lib?tab=readme-ov-file#github-app-pr-reviews)
for setup instructions.

#### LLM Backends

Pyre ships with several built-in LLM backends:

| Backend | Name | Description |
|---------|------|-------------|
| `Pyre.LLM.ReqLLM` | `req_llm` | API-based (default) — any major provider via ReqLLM |
| `Pyre.LLM.ClaudeCLI` | `claude_cli` | Claude CLI subprocess |
| `Pyre.LLM.CursorCLI` | `cursor_cli` | Cursor CLI subprocess |
| `Pyre.LLM.CodexCLI` | `codex_cli` | OpenAI Codex CLI subprocess |

The default backend is `Pyre.LLM.ReqLLM`. To switch backends, set the
`PYRE_LLM_BACKEND` environment variable to the backend's name:

```bash
export PYRE_LLM_BACKEND=claude_cli
```

##### API Keys

When using the `req_llm` backend, set at least one API key:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
export OPENAI_API_KEY=sk-...
```

Model aliases are configured in `config/config.exs`:

```elixir
config :jido_ai,
  model_aliases: %{
    fast: "anthropic:claude-haiku-4-5",
    standard: "anthropic:claude-sonnet-4-20250514",
    advanced: "anthropic:claude-opus-4-20250514"
  }
```

To use a different provider (e.g., OpenAI), change the model alias strings
and set the corresponding API key:

```elixir
config :jido_ai,
  model_aliases: %{
    fast: "openai:gpt-4o-mini",
    standard: "openai:gpt-4o",
    advanced: "openai:o1"
  }
```

### Usage

Run the feature-building pipeline:

```bash
mix pyre.run "Build a products listing page with sorting and filtering"
```

This runs six agents in sequence:

```
Feature Request
  -> Product Manager    (requirements & user stories)
  -> Designer           (UI/UX spec with Tailwind layout)
  -> Programmer         (implementation using Phoenix conventions)
  -> Test Writer        (ExUnit tests)
  -> Code Reviewer      (APPROVE or REJECT)
       -> If REJECT: loop Programmer/TestWriter/Reviewer (up to 3 cycles)
  -> Shipper            (git branch, commit, push, open GitHub PR)
```

Output streams to the terminal token-by-token so you can see each agent
working in real time.

#### Options

| Flag | Short | Description |
|------|-------|-------------|
| `--fast` | `-f` | Use the fastest model for all agents |
| `--dry-run` | `-d` | Print plan without calling LLMs |
| `--verbose` | `-v` | Print diagnostic information |
| `--no-stream` | | Disable streaming (wait for complete responses) |
| `--project-dir` | `-p` | Working directory for agents (default: `.`) |
| `--feature` | `-n` | Feature name to group related runs |
| `--allowed-paths` | | Comma-separated additional directories agents can access |

#### Artifacts

Each run creates a timestamped directory in `priv/pyre/features/<feature>/` containing:

| File | Agent | Content |
|------|-------|---------|
| `00_feature.md` | — | Original feature request |
| `01_requirements.md` | Product Manager | User stories and acceptance criteria |
| `02_design_spec.md` | Designer | UI/UX specifications |
| `03_implementation_summary.md` | Programmer | Code changes made |
| `04_test_summary.md` | Test Writer | Tests written |
| `05_review_verdict.md` | Code Reviewer | APPROVE or REJECT with feedback |
| `06_shipping_summary.md` | Shipper | Branch name, commit, PR URL |

On review rejection cycles, artifacts are versioned (`_v2`, `_v3`).

### Architecture

Pyre is built on three layers:

**Actions** — Each agent role is a [Jido Action](https://hexdocs.pm/jido_action/Jido.Action.html)
with schema-validated inputs and a `run/2` function. Actions are
flow-agnostic: the same `QAReviewer` action can be used in a feature-building
flow, a PR review flow, or any other pipeline.

```
lib/pyre/actions/
  product_manager.ex    # Requirements from feature description
  designer.ex           # UI/UX design spec
  programmer.ex         # Implementation (versioned on review cycles)
  test_writer.ex        # Test coverage (versioned)
  qa_reviewer.ex        # APPROVE/REJECT verdict (reusable across flows)
  shipper.ex            # Git branch, commit, push, and GitHub PR
```

**Flows** — Pipeline drivers that compose actions into a specific workflow.
Each flow defines its phases and valid transitions:

```
lib/pyre/flows/
  feature_build.ex      # planning -> designing -> implementing ->
                        #   testing -> reviewing -> shipping -> complete
```

**Plugins** — Shared utilities used by all actions:

```
lib/pyre/plugins/
  persona.ex            # Loads .md persona files, builds LLM messages
  artifact.ex           # Timestamped run directories, versioned files
```

### Customization

#### Persona files

Edit the persona files in `priv/pyre/personas/` to customize agent behavior
for your project. Each file is a Markdown document used as the system prompt.
The installer will not overwrite files that already exist, so your changes
are preserved across updates.

#### Adding a new flow

Create a new module under `lib/pyre/flows/` that reuses existing actions:

```elixir
defmodule Pyre.Flows.PRReview do
  alias Pyre.Actions.QAReviewer

  def run(pr_diff, opts \\ []) do
    context = %{llm: Keyword.get(opts, :llm, Pyre.LLM), streaming: true}

    with {:ok, result} <- QAReviewer.run(%{
           feature_description: "Review this PR",
           requirements: pr_diff,
           design: "",
           implementation: pr_diff,
           tests: "",
           run_dir: "/tmp/review",
           review_cycle: 1
         }, context) do
      {:ok, result.verdict}
    end
  end
end
```

#### Adding a new action

```elixir
defmodule Pyre.Actions.SecurityReviewer do
  use Jido.Action,
    name: "security_reviewer",
    schema: [
      code: [type: :string, required: true],
      run_dir: [type: :string, required: true]
    ]

  def run(params, context) do
    model = Pyre.Actions.Helpers.resolve_model(:advanced, context)
    {:ok, sys} = Pyre.Plugins.Persona.system_message(:security_reviewer)
    user = Pyre.Plugins.Persona.user_message("Security review", params.code, params.run_dir, "security.md")

    case Pyre.Actions.Helpers.call_llm(context, model, [sys, user]) do
      {:ok, text} -> {:ok, %{review: text}}
      error -> error
    end
  end
end
```

#### Custom LLM backends

You can define your own LLM backend by implementing the `Pyre.LLM` behaviour.
Use `use Pyre.LLM` to get the behaviour and a default `manages_tool_loop?/0`
returning `false`:

```elixir
defmodule MyApp.LLM.Ollama do
  use Pyre.LLM

  @impl true
  def generate(model, messages, opts \\ []) do
    # Call your LLM provider
    {:ok, "response text"}
  end

  @impl true
  def stream(model, messages, opts \\ []) do
    output_fn = Keyword.get(opts, :output_fn, &IO.write/1)
    # Stream tokens via output_fn, return full text
    {:ok, "response text"}
  end

  @impl true
  def chat(model, messages, tools, opts \\ []) do
    # Handle tool-use conversations
    {:ok, "response text"}
  end
end
```

Then register it in your `Pyre.Config` module:

```elixir
defmodule MyApp.Pyre.Config do
  use Pyre.Config

  @impl true
  def list_llm_backends do
    Pyre.Config.included_llm_backends() ++ [
      %{module: MyApp.LLM.Ollama, name: "ollama",
        label: "Ollama", description: "Local models via Ollama"}
    ]
  end
end
```

This makes your backend available via `PYRE_LLM_BACKEND=ollama` and visible
in any UI that calls `Pyre.Config.list_llm_backends/0`.

To set it as the default regardless of env vars, also override `get_llm_backend/1`:

```elixir
@impl true
def get_llm_backend(_arg), do: MyApp.LLM.Ollama
```

For CLI-style backends that manage their own tool-calling loop (like Claude CLI
or Codex CLI), override `manages_tool_loop?/0` to return `true`. This tells
Pyre to call `chat/4` directly instead of routing through the agentic loop.

### Generators

Pyre includes Igniter-based generators that agents use during the pipeline:

- `mix pyre.gen.context` — Generates a context module with CRUD functions
- `mix pyre.gen.live` — Generates LiveView pages with index/show views
- `mix pyre.gen.modal` — Adds a modal component to a LiveView
- `mix pyre.gen.filter` — Adds a filter function to an existing context

### Testing

Actions and flows are testable without LLM calls using the mock:

```elixir
# Test a single action
Process.put(:mock_llm_response, "APPROVE\n\nLooks great!")
{:ok, result} = Pyre.Actions.QAReviewer.run(params, %{llm: Pyre.LLM.Mock, streaming: false})
assert result.verdict == :approve

# Test a full flow with sequenced responses
Process.put(:mock_llm_responses, [
  "Requirements...", "Design...", "Implementation...", "Tests...", "APPROVE\n\nDone."
])
{:ok, state} = Pyre.Flows.FeatureBuild.run("Build a feature", llm: Pyre.LLM.Mock, streaming: false)
assert state.phase == :complete
```

## PyreWeb

> For a fully configured standlone application see [Pyre App](https://github.com/chrislaskey/pyre_app)

The modular web interface dependency for [Pyre](https://github.com/chrislaskey/pyre).

Mounts into an existing Phoenix LiveView application as a
standalone dashboard — similar to
[Phoenix LiveDashboard](https://github.com/phoenixframework/phoenix_live_dashboard).

### Configuration

#### Pyre

Follow the [Pyre app configuration steps](https://github.com/chrislaskey/pyre_lib?tab=readme-ov-file#configuration).

#### Add PyreWeb routes

Add the PyreWeb route to your router:

```elixir
# lib/my_app_web/router.ex
import PyreWeb.Router

scope "/" do
  pipe_through :browser
  pyre_web "/pyre"
end
```

Visit `/pyre` in your browser to see the PyreWeb interface. The `pyre_web`
macro mounts all routes including the GitHub webhook endpoint
(`POST /pyre/webhooks/github`). The webhook controller skips CSRF
protection automatically since it receives requests from GitHub, not a
browser.

#### Lifecycle hooks

Pyre and PyreWeb dispatches lifecycle events to a configurable callback module. The default
behaviour can be overwritten by creating a custom module and defining callback functions.

You can use the same module for both `Pyre.Config` and `PyreWeb.Config`:

```elixir
defmodule MyApp.Pyre.Config do
  use Pyre.Config
  use PyreWeb.Config

  # Pyre Callbacks

  @impl Pyre.Config
  def after_flow_complete(%Pyre.Events.FlowCompleted{} = event) do
    MyApp.Telemetry.emit(:pyre_flow_complete, %{elapsed_ms: event.elapsed_ms})
    :ok
  end

  # PyreWeb Callbacks

  @impl PyreWeb.Config
  def authorize_socket_connect(params, _connect_info) do
    case Map.get(params, "token") do
      nil -> {:error, :missing_token}
      token -> if MyApp.Auth.valid_token?(token), do: :ok, else: {:error, :invalid_token}
    end
  end
end
```

Then register it in your config. Each library reads its own application
environment, so both entries are required:

```elixir
# config/config.exs
config :pyre, config: MyApp.Pyre.Config
config :pyre_web, config: MyApp.Pyre.Config
```

Any callback not overridden returns `:ok` by default. Exceptions in callbacks
are rescued and logged — they never crash the running flow.

#### Supervision tree

PyreWeb is a library — it has no OTP application of its own. Optional
processes are added to the host app's supervision tree as needed:

```elixir
# lib/my_app/application.ex
children = [
  # ... existing children ...
  # {Phoenix.PubSub, name: MyApp.PubSub}
  PyreWeb.Presence,
  PyreWeb.ReviewQueue
  # MyAppWeb.Endpoint
]
```

| Child | Purpose | Required? |
|-------|---------|-----------|
| `PyreWeb.Presence` | Tracks connected native app instances on the homepage | Optional |
| `PyreWeb.ReviewQueue` | Processes `@mention`-triggered PR review jobs from webhooks | Optional |

Both modules expose a `running?/0` function. When not started, their
features gracefully no-op (e.g. webhook mentions are silently ignored).

#### (Optional) Use remote macOS hosts as runners using PyreNative app

PyreWeb supports using multiple remote macOS hosts as runners. This lets you leverage fully configured development environments and load balance requests across your LLM subscriptions. Setup is easy, see:

> The [Pyre Native App](https://github.com/chrislaskey/pyre_native) repository

#### (Optional) GitHub App

PyreWeb supports `@mention`-triggered PR reviews via a GitHub App. When someone
comments `@your-bot review` on a pull request, the webhook controller parses the
mention, enqueues the review job, and dispatches it to `Pyre.RemoteReview` in
pyre_lib.

**Flow**: Webhook → `WebhookController` (verify HMAC + parse) → `PyreWeb.MentionParser` → `PyreWeb.ReviewQueue` (rate-limited, bounded concurrency) → `Pyre.RemoteReview.run/1`

##### Supported commands

| Command | Example | Description |
|---------|---------|-------------|
| `review` | `@bot review` | Run a full code review on the PR |
| `explain` | `@bot explain the auth changes` | Explain specific code |
| `help` | `@bot help` | Show available commands |
| *(other)* | `@bot what about error handling?` | Follow-up question on previous review |

Mentions inside code blocks or blockquotes are ignored.

##### Setup

1. Add `PyreWeb.ReviewQueue` to your supervision tree (see [Supervision tree](#supervision-tree))
2. Visit `/pyre/settings/github-apps/new` to register a GitHub App via manifest flow
3. Configure the webhook secret and bot slug and update `config/runtime.exs`:

```elixir
# config/runtime.exs
config :pyre, :github_apps, [
  if System.get_env("PYRE_GITHUB_APP_ID") do
    [
      app_id: System.get_env("PYRE_GITHUB_APP_ID"),
      private_key: System.get_env("PYRE_GITHUB_APP_PRIVATE_KEY"),
      webhook_secret: System.get_env("PYRE_GITHUB_WEBHOOK_SECRET"),
      bot_slug: System.get_env("PYRE_GITHUB_APP_BOT_SLUG")
    ]
  end
]
```

4. Implement the `update_github_app/1` and `list_github_apps/0` callbacks in your
   config module to persist the App credentials (see [Authorization Hooks](#authorization-hooks))

### Pages

| Route | Description |
|-------|-------------|
| `/pyre` | Home page with links to start or view runs |
| `/pyre/runs` | List of all pipeline runs with status |
| `/pyre/runs/new` | Form to start a new pipeline run |
| `/pyre/runs/:id` | Streaming output for a specific run |
| `/pyre/settings` | Settings index with links to configuration pages |
| `/pyre/settings/github-apps/new` | GitHub App registration via manifest flow |
| `POST /pyre/webhooks/github` | GitHub webhook endpoint (API, not browser) |

Run processes are managed by `Pyre.RunServer` — a GenServer per run, supervised
by a DynamicSupervisor and registered in a Registry. This means:

- **Runs survive page refreshes**: output is buffered in the GenServer and
  replayed when you navigate back to a run page.
- **Real-time streaming**: LiveViews subscribe to PubSub for live updates as
  agents produce output.
- **Multiple viewers**: any number of browser tabs can watch the same run.

### File Attachments

The "New Run" form supports file attachments via paste, drag-and-drop, or file
browser. Accepted formats include images (PNG, JPG, GIF, WebP) and text files
(Markdown, JSON, CSV, HTML, CSS, JS). Up to 10 files, 10 MB each.

Image attachments are sent as vision content to the LLM, so agents like the
Designer can reference pasted screenshots or mockups directly.

### How it works

PyreWeb bundles its own JavaScript that includes the Phoenix LiveView client
library. The JS is embedded at compile time and served via a versioned route
(`/pyre/js-<md5hash>`). The `<script>` tag is included automatically in
PyreWeb's isolated root layout — no changes to your app's asset pipeline are
required.

The layout also loads [DaisyUI](https://daisyui.com/) and
[Tailwind CSS](https://tailwindcss.com/) from CDN for styling, keeping PyreWeb
fully independent of your app's CSS.

### Authentication

Use the `:on_mount` option to protect the route with your app's
authentication:

```elixir
pyre_web "/pyre",
  on_mount: [{MyAppWeb.Auth, :ensure_admin}]
```

### Authorization Hooks

PyreWeb provides 6 authorization hooks that let your app gate WebSocket
connections, channel joins, run creation, run control, remote action
dispatch, and webhook processing. Create a module that `use PyreWeb.Config`
and override the callbacks you need:

```elixir
defmodule MyApp.Pyre.Config do
  use Pyre.Config
  use PyreWeb.Config

  # --- Pyre lifecycle hooks (optional) ---

  @impl Pyre.Config
  def after_flow_complete(%Pyre.Events.FlowCompleted{} = event) do
    MyApp.Telemetry.emit(:pyre_flow_complete, %{elapsed_ms: event.elapsed_ms})
    :ok
  end

  # --- PyreWeb authorization hooks ---

  @impl PyreWeb.Config
  def authorize_socket_connect(params, _connect_info) do
    case Map.get(params, "token") do
      nil -> {:error, :missing_token}
      token -> if MyApp.Auth.valid_token?(token), do: :ok, else: {:error, :invalid_token}
    end
  end

  @impl PyreWeb.Config
  def authorize_run_create(_run_params, socket) do
    if socket.assigns[:current_user], do: :ok, else: {:error, :unauthenticated}
  end
end
```

Then register the module in your config. Both libraries can share one module
since the callback names don't overlap (`after_*` for Pyre, `authorize_*` for
PyreWeb). Each library reads its own application environment, so both entries
are required:

```elixir
# config/config.exs
config :pyre, config: MyApp.Pyre.Config
config :pyre_web, config: MyApp.Pyre.Config
```

The 6 authorization hooks and their arguments:

| Hook | Arguments | Used in |
|------|-----------|---------|
| `authorize_socket_connect` | `(params, connect_info)` | `PyreWeb.Socket` |
| `authorize_channel_join` | `(topic, socket)` | `PyreWeb.Channel` |
| `authorize_run_create` | `(run_params, socket)` | New run form |
| `authorize_run_control` | `(action, socket)` | Run show (stop, toggle, reply) |
| `authorize_remote_action` | `(action, socket)` | Home page action dispatch |
| `authorize_webhook` | `(event, payload)` | `PyreWeb.WebhookController` |

PyreWeb.Config also provides persistence callbacks for GitHub App credentials:

| Callback | Arguments | Description |
|----------|-----------|-------------|
| `update_github_app` | `(credentials)` | Persist GitHub App credentials after setup |
| `list_github_apps` | `()` | Load all configured GitHub Apps (returns list of maps) |

All authorization callbacks return `:ok | {:error, term()}`. Defaults permit
all operations. Exceptions in callbacks are rescued and return `:ok`
(fail-open) to avoid locking users out when a hook crashes.

#### Render Hooks

PyreWeb provides render callbacks that let your app inject custom HEEx markup
into the dashboard UI:

| Callback | Arguments | Description |
|----------|-----------|-------------|
| `sidebar_footer` | `(assigns)` | Renders content at the bottom of the sidebar |

The `assigns` map includes `:current_page`, `:prefix`, and `:uri` from the
sidebar component. The default implementation renders nothing.

```elixir
@impl PyreWeb.Config
def sidebar_footer(assigns) do
  import Phoenix.Component, only: [sigil_H: 2]

  ~H"""
  <div class="border-t border-base-300 pt-3 mt-3">
    <ul class="menu w-full gap-y-1">
      <li>
        <a href="/admin">Admin</a>
      </li>
    </ul>
  </div>
  """
end
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `:on_mount` | `nil` | LiveView `on_mount` callbacks for auth |
| `:live_socket_path` | `"/live"` | Must match your endpoint's LiveView socket |
| `:live_session_name` | `:pyre_web` | Session name (only needed for multiple mounts) |
