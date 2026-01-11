"""Streamlit UI for flight intelligence."""

import os
from datetime import datetime, timedelta

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import requests
import streamlit as st

# API configuration
API_BASE = os.getenv("API_BASE_URL", "http://flight-api:8000")

st.set_page_config(
    page_title="Flight Intelligence",
    page_icon="✈️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Custom CSS
st.markdown(
    """
<style>
    .recommendation-card {
        padding: 20px;
        border-radius: 10px;
        margin: 10px 0;
    }
    .buy {
        background-color: #d4edda;
        border-left: 5px solid #28a745;
    }
    .wait {
        background-color: #fff3cd;
        border-left: 5px solid #ffc107;
    }
    .hold {
        background-color: #d1ecf1;
        border-left: 5px solid #17a2b8;
    }
</style>
""",
    unsafe_allow_html=True,
)


def call_api(endpoint: str, params: dict = None) -> dict:
    """Call the flight intelligence API."""
    try:
        url = f"{API_BASE}{endpoint}"
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        st.error(f"API Error: {e}")
        return {}


# Sidebar
st.sidebar.title("✈️ Flight Intelligence")
st.sidebar.markdown("---")

# Filters
st.sidebar.subheader("Search Filters")

origins = st.sidebar.multiselect(
    "Origin Airports",
    ["AMS", "EIN", "RTM", "BRU"],
    default=["AMS", "EIN"],
)

destinations = st.sidebar.multiselect(
    "Destination Airports (Crete)",
    ["HER", "CHQ"],
    default=["HER", "CHQ"],
)

# Date range
today = datetime.now()
default_start = today + timedelta(days=30)
default_end = today + timedelta(days=120)

date_start = st.sidebar.date_input(
    "Departure Date Range - Start",
    value=default_start,
    min_value=today,
)

date_end = st.sidebar.date_input(
    "Departure Date Range - End",
    value=default_end,
    min_value=today,
)

# Stay duration
stay_range = st.sidebar.slider(
    "Stay Duration (days)",
    min_value=3,
    max_value=28,
    value=(7, 14),
)

# Main content
st.title("✈️ Flight Price Intelligence")
st.markdown("### Find the best deals from NL/BE to Crete")

# Tabs
tab1, tab2, tab3, tab4 = st.tabs(["📊 Best Offers", "📈 Price History", "🎯 Recommendations", "🤖 AI Assistant"])

with tab1:
    st.subheader("Best Flight Offers")

    if st.button("🔄 Refresh Offers"):
        st.rerun()

    if origins and destinations:
        # Fetch best offers
        params = {
            "origins": ",".join(origins),
            "destinations": ",".join(destinations),
            "depart_date_start": date_start.strftime("%Y-%m-%d"),
            "depart_date_end": date_end.strftime("%Y-%m-%d"),
            "min_stay": stay_range[0],
            "max_stay": stay_range[1],
            "limit": 100,
        }

        with st.spinner("Loading offers..."):
            data = call_api("/offers/best", params)

        if data and "offers" in data:
            offers = data["offers"]

            if offers:
                st.success(f"Found {len(offers)} offers")

                # Convert to DataFrame
                df = pd.DataFrame(offers)

                # Create heatmap data
                if not df.empty and "stay_days" in df.columns:
                    # Pivot table for heatmap
                    pivot_data = df.pivot_table(
                        values="price",
                        index="stay_days",
                        columns="depart_date",
                        aggfunc="min",
                    )

                    st.subheader("Price Heatmap")
                    st.markdown("_Lower prices are shown in green_")

                    # Display heatmap
                    fig = px.imshow(
                        pivot_data,
                        labels=dict(x="Departure Date", y="Stay Days", color="Price (€)"),
                        aspect="auto",
                        color_continuous_scale="RdYlGn_r",
                    )
                    fig.update_layout(height=400)
                    st.plotly_chart(fig, use_container_width=True)

                # Table view
                st.subheader("All Offers")

                # Format DataFrame for display
                display_df = df[
                    [
                        "origin",
                        "destination",
                        "depart_date",
                        "return_date",
                        "stay_days",
                        "price",
                        "airline",
                        "stops",
                    ]
                ].copy()
                display_df["price"] = display_df["price"].apply(lambda x: f"€{x:.2f}")
                display_df = display_df.sort_values("price")

                st.dataframe(display_df, use_container_width=True, height=400)

            else:
                st.warning("No offers found for the selected criteria")
    else:
        st.info("Please select at least one origin and one destination")

with tab2:
    st.subheader("Price History")

    col1, col2, col3 = st.columns(3)

    with col1:
        hist_origin = st.selectbox("Origin", origins if origins else ["AMS"])

    with col2:
        hist_dest = st.selectbox("Destination", destinations if destinations else ["HER"])

    with col3:
        hist_depart = st.date_input(
            "Departure Date",
            value=default_start,
            min_value=today,
        )

    hist_return = st.date_input(
        "Return Date",
        value=default_start + timedelta(days=10),
        min_value=today,
    )

    if st.button("Get Price History"):
        params = {
            "origin": hist_origin,
            "destination": hist_dest,
            "depart_date": hist_depart.strftime("%Y-%m-%d"),
            "return_date": hist_return.strftime("%Y-%m-%d"),
        }

        with st.spinner("Loading history..."):
            history_data = call_api("/history", params)

        if history_data and "history" in history_data:
            history = history_data["history"]

            if history:
                df_hist = pd.DataFrame(history)
                df_hist["date"] = pd.to_datetime(df_hist["date"])

                # Line chart
                fig = go.Figure()

                fig.add_trace(
                    go.Scatter(
                        x=df_hist["date"],
                        y=df_hist["min_price"],
                        mode="lines+markers",
                        name="Minimum Price",
                        line=dict(color="green", width=2),
                    )
                )

                fig.add_trace(
                    go.Scatter(
                        x=df_hist["date"],
                        y=df_hist["avg_price"],
                        mode="lines+markers",
                        name="Average Price",
                        line=dict(color="blue", width=2, dash="dash"),
                    )
                )

                fig.update_layout(
                    title=f"Price History: {hist_origin} → {hist_dest}",
                    xaxis_title="Date",
                    yaxis_title="Price (€)",
                    hovermode="x unified",
                    height=400,
                )

                st.plotly_chart(fig, use_container_width=True)

                # Stats
                col1, col2, col3 = st.columns(3)
                with col1:
                    st.metric("Current Best", f"€{df_hist['min_price'].iloc[-1]:.2f}")
                with col2:
                    st.metric("Historical Low", f"€{df_hist['min_price'].min():.2f}")
                with col3:
                    st.metric("Average", f"€{df_hist['avg_price'].mean():.2f}")

            else:
                st.warning("No historical data available")

with tab3:
    st.subheader("Buy/Wait Recommendation")

    col1, col2 = st.columns(2)

    with col1:
        reco_origin = st.selectbox("From", origins if origins else ["AMS"], key="reco_origin")
        reco_depart = st.date_input(
            "Depart",
            value=default_start,
            min_value=today,
            key="reco_depart",
        )

    with col2:
        reco_dest = st.selectbox(
            "To", destinations if destinations else ["HER"], key="reco_dest"
        )
        reco_return = st.date_input(
            "Return",
            value=default_start + timedelta(days=10),
            min_value=today,
            key="reco_return",
        )

    if st.button("Get Recommendation"):
        params = {
            "origin": reco_origin,
            "destination": reco_dest,
            "depart_date": reco_depart.strftime("%Y-%m-%d"),
            "return_date": reco_return.strftime("%Y-%m-%d"),
        }

        with st.spinner("Analyzing..."):
            reco_data = call_api("/recommendation", params)

        if reco_data and "action" in reco_data:
            action = reco_data["action"]
            confidence = reco_data["confidence"]
            current_price = reco_data.get("current_price", 0)
            rationale = reco_data.get("rationale", {})

            # Display recommendation card
            card_class = action.lower()
            emoji = "✅" if action == "BUY" else "⏳" if action == "WAIT" else "🤔"

            st.markdown(
                f"""
            <div class="recommendation-card {card_class}">
                <h2>{emoji} {action}</h2>
                <p><strong>Confidence:</strong> {confidence * 100:.0f}%</p>
                <p><strong>Current Price:</strong> €{current_price:.2f}</p>
            </div>
            """,
                unsafe_allow_html=True,
            )

            # Rationale
            st.subheader("Analysis")
            st.write(rationale.get("reason", "No specific reason provided"))

            if "rolling_min" in rationale:
                col1, col2, col3 = st.columns(3)
                with col1:
                    st.metric("Historical Low", f"€{rationale['rolling_min']:.2f}")
                with col2:
                    st.metric("Median Price", f"€{rationale['rolling_median']:.2f}")
                with col3:
                    if "threshold" in rationale:
                        st.metric("Buy Threshold", f"€{rationale['threshold']:.2f}")

            if "days_to_departure" in rationale:
                st.info(f"📅 {rationale['days_to_departure']} days until departure")

with tab4:
    st.subheader("🤖 AI Flight Assistant")
    st.markdown("Ask questions in natural language about flight prices and recommendations.")

    # Chat interface
    if "messages" not in st.session_state:
        st.session_state.messages = []

    # Display chat history
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])

    # User input
    if prompt := st.chat_input("Ask me about flights..."):
        # Add user message
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        # Get agent response
        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                try:
                    response = requests.post(
                        f"{API_BASE}/agent/query",
                        json={"question": prompt},
                        timeout=30,
                    )
                    response.raise_for_status()
                    agent_response = response.json()

                    if agent_response.get("agent_available"):
                        answer = agent_response.get("response", "No response")
                    else:
                        answer = agent_response.get(
                            "response",
                            "AI assistant is not available. Please enable it in settings.",
                        )

                    st.markdown(answer)
                    st.session_state.messages.append({"role": "assistant", "content": answer})

                except Exception as e:
                    error_msg = f"Error: {str(e)}"
                    st.error(error_msg)
                    st.session_state.messages.append({"role": "assistant", "content": error_msg})

# Footer
st.sidebar.markdown("---")
st.sidebar.info(
    """
**Flight Intelligence v0.1.0**

Monitor flight prices from NL/BE to Crete and get smart buy/wait recommendations.
"""
)
