defmodule Handroll.Repo do
  use Ecto.Repo,
    otp_app: :handroll,
    adapter: Ecto.Adapters.Postgres
end
