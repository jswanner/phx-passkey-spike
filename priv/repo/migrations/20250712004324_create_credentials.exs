defmodule Handroll.Repo.Migrations.CreateCredentials do
  use Ecto.Migration

  def change do
    create table(:credentials, primary_key: false) do
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :description, :text, primary_key: true
      add :id, :binary, primary_key: true
      add :public_key, :binary, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:credentials, [:account_id])
  end
end
