"""Initial migration - create all tables

Revision ID: 001_initial
Revises: 
Create Date: 2024-01-11

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '001_initial'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create routes table
    op.create_table(
        'routes',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('origin_airport', sa.String(length=3), nullable=False),
        sa.Column('dest_airport', sa.String(length=3), nullable=False),
        sa.Column('active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('created_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('origin_airport', 'dest_airport', name='uq_route')
    )
    op.create_index('idx_route_active', 'routes', ['origin_airport', 'dest_airport', 'active'])

    # Create search_configs table
    op.create_table(
        'search_configs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('origins', postgresql.ARRAY(sa.String()), nullable=False),
        sa.Column('destinations', postgresql.ARRAY(sa.String()), nullable=False),
        sa.Column('start_date', sa.String(length=10), nullable=False),
        sa.Column('end_date', sa.String(length=10), nullable=False),
        sa.Column('min_stay_days', sa.Integer(), nullable=False),
        sa.Column('max_stay_days', sa.Integer(), nullable=False),
        sa.Column('cabin', sa.String(length=20), server_default='ECONOMY'),
        sa.Column('max_stops', sa.Integer(), server_default='2'),
        sa.Column('currency', sa.String(length=3), server_default='EUR'),
        sa.Column('active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('created_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('name')
    )

    # Create price_snapshots table
    op.create_table(
        'price_snapshots',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('collected_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.Column('provider', sa.String(length=50), nullable=False),
        sa.Column('origin', sa.String(length=3), nullable=False),
        sa.Column('destination', sa.String(length=3), nullable=False),
        sa.Column('depart_date', sa.String(length=10), nullable=False),
        sa.Column('return_date', sa.String(length=10), nullable=True),
        sa.Column('stay_days', sa.Integer(), nullable=True),
        sa.Column('price_total', sa.Float(), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=False),
        sa.Column('airline', sa.String(length=50), nullable=True),
        sa.Column('stops', sa.Integer(), nullable=True),
        sa.Column('deep_link', sa.Text(), nullable=True),
        sa.Column('raw_json', postgresql.JSON(), nullable=True),
        sa.Column('hash', sa.String(length=64), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('hash')
    )
    op.create_index('idx_snapshot_collected', 'price_snapshots', ['collected_at', 'provider'])
    op.create_index('idx_snapshot_hash', 'price_snapshots', ['hash'])
    op.create_index('idx_snapshot_origin', 'price_snapshots', ['origin'])
    op.create_index('idx_snapshot_destination', 'price_snapshots', ['destination'])
    op.create_index('idx_snapshot_depart_date', 'price_snapshots', ['depart_date'])
    op.create_index('idx_snapshot_return_date', 'price_snapshots', ['return_date'])
    op.create_index('idx_snapshot_route_date', 'price_snapshots', ['origin', 'destination', 'depart_date', 'return_date'])
    op.create_index('idx_snapshot_price', 'price_snapshots', ['origin', 'destination', 'price_total'])

    # Create daily_best table
    op.create_table(
        'daily_best',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('date_bucket', sa.String(length=10), nullable=False),
        sa.Column('origin', sa.String(length=3), nullable=False),
        sa.Column('destination', sa.String(length=3), nullable=False),
        sa.Column('depart_date', sa.String(length=10), nullable=False),
        sa.Column('return_date', sa.String(length=10), nullable=True),
        sa.Column('stay_days', sa.Integer(), nullable=True),
        sa.Column('best_price', sa.Float(), nullable=False),
        sa.Column('provider', sa.String(length=50), nullable=False),
        sa.Column('updated_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('date_bucket', 'origin', 'destination', 'depart_date', 'return_date', name='uq_daily_best')
    )
    op.create_index('idx_daily_best_date_bucket', 'daily_best', ['date_bucket'])
    op.create_index('idx_daily_best_origin', 'daily_best', ['origin'])
    op.create_index('idx_daily_best_destination', 'daily_best', ['destination'])
    op.create_index('idx_daily_best_depart_date', 'daily_best', ['depart_date'])
    op.create_index('idx_daily_best_lookup', 'daily_best', ['origin', 'destination', 'depart_date', 'return_date', 'date_bucket'])

    # Create recommendations table
    op.create_table(
        'recommendations',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('created_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.Column('origin', sa.String(length=3), nullable=False),
        sa.Column('destination', sa.String(length=3), nullable=False),
        sa.Column('depart_date', sa.String(length=10), nullable=False),
        sa.Column('return_date', sa.String(length=10), nullable=True),
        sa.Column('stay_days', sa.Integer(), nullable=True),
        sa.Column('action', sa.String(length=10), nullable=False),
        sa.Column('confidence', sa.Float(), nullable=False),
        sa.Column('threshold_price', sa.Float(), nullable=True),
        sa.Column('current_price', sa.Float(), nullable=False),
        sa.Column('rationale', postgresql.JSON(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('idx_reco_created_at', 'recommendations', ['created_at'])
    op.create_index('idx_reco_origin', 'recommendations', ['origin'])
    op.create_index('idx_reco_destination', 'recommendations', ['destination'])
    op.create_index('idx_reco_lookup', 'recommendations', ['origin', 'destination', 'depart_date', 'return_date'])


def downgrade() -> None:
    op.drop_table('recommendations')
    op.drop_table('daily_best')
    op.drop_table('price_snapshots')
    op.drop_table('search_configs')
    op.drop_table('routes')
