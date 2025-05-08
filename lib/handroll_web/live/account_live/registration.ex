defmodule HandrollWeb.AccountLive.Registration do
  use HandrollWeb, :live_view

  alias Handroll.Accounts
  alias Handroll.Accounts.Account

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <.header class="text-center">
          Register for an account
          <:subtitle>
            Already registered?
            <.link navigate={~p"/accounts/log-in"} class="font-semibold text-brand hover:underline">
              Log in
            </.link>
            to your account now.
          </:subtitle>
        </.header>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            required
            phx-mounted={JS.focus()}
          />

          <.button variant="primary" phx-disable-with="Creating account..." class="w-full">
            Create an account
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, %{assigns: %{current_scope: %{account: account}}} = socket)
      when not is_nil(account) do
    {:ok, redirect(socket, to: HandrollWeb.AccountAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_account_email(%Account{})

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"account" => account_params}, socket) do
    case Accounts.register_account(account_params) do
      {:ok, account} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            account,
            &url(~p"/accounts/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{account.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/accounts/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"account" => account_params}, socket) do
    changeset = Accounts.change_account_email(%Account{}, account_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "account")
    assign(socket, form: form)
  end
end
