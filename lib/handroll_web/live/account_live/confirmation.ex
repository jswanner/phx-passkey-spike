defmodule HandrollWeb.AccountLive.Confirmation do
  use HandrollWeb, :live_view

  alias Handroll.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <.header class="text-center">Welcome {@account.email}</.header>

        <.form
          :if={!@account.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-submit="submit"
          action={~p"/accounts/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.input
            :if={!@current_scope}
            field={@form[:remember_me]}
            type="checkbox"
            label="Keep me logged in"
          />
          <.button variant="primary" phx-disable-with="Confirming..." class="w-full">
            Confirm my account
          </.button>
        </.form>

        <.form
          :if={@account.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          action={~p"/accounts/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.input
            :if={!@current_scope}
            field={@form[:remember_me]}
            type="checkbox"
            label="Keep me logged in"
          />
          <.button variant="primary" phx-disable-with="Logging in..." class="w-full">Log in</.button>
        </.form>

        <p :if={!@account.confirmed_at} class="alert alert-outline mt-8">
          Tip: If you prefer passwords, you can enable them in the account settings.
        </p>
      </div>
    </Layouts.app>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    if account = Accounts.get_account_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "account")

      {:ok, assign(socket, account: account, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/accounts/log-in")}
    end
  end

  def handle_event("submit", %{"account" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "account"), trigger_submit: true)}
  end
end
