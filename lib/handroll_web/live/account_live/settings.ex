defmodule HandrollWeb.AccountLive.Settings do
  use HandrollWeb, :live_view

  on_mount {HandrollWeb.AccountAuth, :require_sudo_mode}

  alias Handroll.Accounts
  alias Handroll.Accounts.Credential

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header class="text-center">
        Account Settings
        <:subtitle>Manage your account email address and password settings</:subtitle>
      </.header>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/accounts/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_account_email"
          autocomplete="username"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>

      <div id="publicKeyCredential" phx-hook="createCredential">
        <div :for={credential <- @credentials}>{credential.description}</div>
        <.button
          :if={@capabilities["conditionalCreate"] && !@attested_credential}
          phx-click={JS.dispatch("create_credential")}
        >
          Add Passkey
        </.button>
        <.form
          :if={@attested_credential}
          for={@credential_form}
          id="credential_form"
          phx-submit="create_credential"
          phx-change="validate_credential"
        >
          <.input field={@credential_form[:description]} type="text" label="Description" required />
          <.button variant="primary" phx-disable-with="Changing...">Create Passkey</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_account_email(socket.assigns.current_scope.account, token) do
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/accounts/settings")}
  end

  def mount(_params, _session, socket) do
    account = socket.assigns.current_scope.account
    credentials = Accounts.list_credentials(socket.assigns.current_scope)
    credential_changeset = Accounts.change_credential(%Credential{}, %{})
    email_changeset = Accounts.change_account_email(account, %{}, validate_email: false)
    password_changeset = Accounts.change_account_password(account, %{}, hash_password: false)

    socket =
      socket
      |> assign(:attested_credential, nil)
      |> assign(:capabilities, %{})
      |> assign(:credential_form, to_form(credential_changeset))
      |> assign(:credentials, credentials)
      |> assign(:current_email, account.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  def handle_event("generate_credential_registration", _params, socket) do
    account = socket.assigns.current_scope.account

    challenge =
      Wax.new_registration_challenge(
        origin: HandrollWeb.Endpoint.url(),
        rp_id: HandrollWeb.Endpoint.host()
      )

    reply = %{
      authenticatorSelection: %{
        requireResidentKey: true,
        residentKey: "required",
        userVerification: challenge.user_verification
      },
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      extensions: %{credProps: true},
      pubKeyCredParams: [%{alg: -7, type: "public-key"}, %{alg: -257, type: "public-key"}],
      rp: %{id: challenge.rp_id, name: "Passkey Test"},
      user: %{
        displayName: account.email,
        id: Base.url_encode64(account.id, padding: false),
        name: account.email
      }
    }

    {:reply, reply, assign(socket, :challenge, challenge)}
  end

  def handle_event("store_credential", params, socket) do
    socket =
      with {:ok, attestation_object} <-
             Base.decode64(params["credential"]["response"]["attestationObject"]),
           {:ok, client_data} <-
             Base.decode64(params["credential"]["response"]["clientDataJSON"]),
           {:ok, {auth_data, _}} <-
             Wax.register(attestation_object, client_data, socket.assigns.challenge) do
        assign(socket, :attested_credential, %{
          "id" => auth_data.attested_credential_data.credential_id,
          "public_key" => auth_data.attested_credential_data.credential_public_key
        })
      else
        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"account" => account_params} = params

    email_form =
      socket.assigns.current_scope.account
      |> Accounts.change_account_email(account_params, validate_email: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"account" => account_params} = params
    account = socket.assigns.current_scope.account
    true = Accounts.sudo_mode?(account)

    case Accounts.change_account_email(account, account_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_account_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          account.email,
          &url(~p"/accounts/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"account" => account_params} = params

    password_form =
      socket.assigns.current_scope.account
      |> Accounts.change_account_password(account_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("create_credential", params, socket) do
    scope = socket.assigns.current_scope
    %{"credential" => credential_params} = params
    credential_params = Map.merge(credential_params, socket.assigns.attested_credential)

    socket =
      case Accounts.create_credential(scope, credential_params) do
        {:ok, _} ->
          socket
          |> assign(:attested_credential, nil)
          |> assign(:credential_form, Accounts.change_credential(%Credential{}, %{}) |> to_form())
          |> assign(:credentials, Accounts.list_credentials(scope))

        {:error, %Ecto.Changeset{} = changeset} ->
          assign(socket, :credential_form, to_form(changeset))
      end

    {:noreply, socket}
  end

  def handle_event("update_capabilities", params, socket) do
    {:noreply, assign(socket, :capabilities, params)}
  end

  def handle_event("validate_credential", params, socket) do
    %{"credential" => credential_params} = params

    credential_form =
      %Credential{}
      |> Accounts.change_credential(credential_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, credential_form: credential_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"account" => account_params} = params
    account = socket.assigns.current_scope.account
    true = Accounts.sudo_mode?(account)

    case Accounts.change_account_password(account, account_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
