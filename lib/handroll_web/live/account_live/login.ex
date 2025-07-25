defmodule HandrollWeb.AccountLive.Login do
  use HandrollWeb, :live_view

  alias Handroll.Accounts
  alias Handroll.Accounts.AccountToken

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <.header class="text-center">
          <p>Log in</p>
          <:subtitle>
            <%= if @current_scope do %>
              You need to reauthenticate to perform sensitive actions on your account.
            <% else %>
              Don't have an account? <.link
                navigate={~p"/accounts/register"}
                class="font-semibold text-brand hover:underline"
                phx-no-format
              >Sign up</.link> for an account now.
            <% end %>
          </:subtitle>
        </.header>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/accounts/log-in"}
          phx-hook="getCredential"
          phx-submit={JS.dispatch("abort_get_credential") |> JS.push("submit_magic")}
          phx-trigger-action={@trigger_passkey_submit}
        >
          <input type="hidden" name="account[passkey]" value={@token} />
          <.input
            autocomplete="username webauthn"
            autofocus
            field={f[:email]}
            label="Email"
            readonly={!!@current_scope}
            required
            type="email"
          />
          <.button class="w-full" variant="primary">
            Log in with email <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">or</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/accounts/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_password_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
          />
          <.input
            :if={!@current_scope}
            field={f[:remember_me]}
            type="checkbox"
            label="Keep me logged in"
          />
          <.button class="w-full" variant="primary">
            Log in <span aria-hidden="true">→</span>
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:account), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "account")

    {:ok,
     assign(socket,
       form: form,
       token: nil,
       trigger_passkey_submit: false,
       trigger_password_submit: false
     )}
  end

  def handle_event("authenticate_credential", params, socket) do
    with {:ok, bin_auth_data} <-
           Base.decode64(params["credential"]["response"]["authenticatorData"], padding: false),
         {:ok, client_data} <-
           Base.decode64(params["credential"]["response"]["clientDataJSON"], padding: false),
         {:ok, credential_id} <-
           Base.url_decode64(params["credential"]["id"], padding: false),
         {:ok, signature} <-
           Base.decode64(params["credential"]["response"]["signature"], padding: false),
         credential <- Accounts.get_credential!(credential_id),
         {:ok, _auth_data} <-
           Wax.authenticate(
             credential_id,
             bin_auth_data,
             signature,
             client_data,
             socket.assigns.challenge,
             [{credential.id, credential.public_key}]
           ),
         {encoded_token, account_token} <-
           AccountToken.build_email_token(credential.account, "login"),
         {:ok, _} <- Handroll.Repo.insert(account_token) do
      {:noreply, assign(socket, token: encoded_token, trigger_passkey_submit: true)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Passkey authentication failed :(")}
    end
  end

  def handle_event("generate_credential_authentication", params, socket) do
    challenge =
      Wax.new_authentication_challenge(
        origin: HandrollWeb.Endpoint.url(),
        rp_id: HandrollWeb.Endpoint.host()
      )

    reply = %{
      allowCredentials: challenge.allow_credentials,
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rpId: challenge.rp_id,
      userVerification: challenge.user_verification
    }

    {:reply, reply, assign(socket, :challenge, challenge)}
  end

  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_password_submit, true)}
  end

  def handle_event("submit_magic", %{"account" => %{"email" => email}}, socket) do
    if account = Accounts.get_account_by_email(email) do
      Accounts.deliver_login_instructions(
        account,
        &url(~p"/accounts/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/accounts/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:handroll, Handroll.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
