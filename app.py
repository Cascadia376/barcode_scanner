import streamlit as st
import pandas as pd
from pathlib import Path
from io import BytesIO
import time
import streamlit.components.v1 as components

# --- Page Configuration ---
st.set_page_config(page_title="Inventory Scanner", layout="centered")

# --- File Paths ---
XLSX_FILE = Path("counts.xlsx")
LOOKUP_FILE = Path("Barcode Lookup.xlsx")  # Must be present in repo/deployment

# --- Load Lookup Table ---
@st.cache_data
def load_lookup():
    df = pd.read_excel(LOOKUP_FILE)
    df["UPC"] = df["UPC"].astype(str).str.strip().str.replace(".0", "", regex=False)
    df["SKU"] = df["SKU"].astype(str).str.strip()
    return df.set_index("UPC")

lookup_df = load_lookup()
lookup_by_sku = lookup_df.reset_index().set_index("SKU")

# --- Load or Initialize Counts ---
if XLSX_FILE.exists():
    df = pd.read_excel(XLSX_FILE)
else:
    df = pd.DataFrame(columns=["SKU", "Counted Qty"])

# --- Focus Management ---
def set_focus(field_id):
    components.html(
        f"""
        <script>
        const interval = setInterval(function() {{
            var input = window.parent.document.querySelector('input[id="{field_id}"]');
            if (input) {{
                input.focus();
                clearInterval(interval);
            }}
        }}, 100);
        </script>
        """,
        height=0,
    )

# --- Excel Download Helper ---
def get_excel_download(df):
    output = BytesIO()
    df.to_excel(output, index=False)
    return output.getvalue()

# --- Session State Setup ---
if "quantity" not in st.session_state:
    st.session_state["quantity"] = 0

if "reset_qty" not in st.session_state:
    st.session_state["reset_qty"] = False

if "barcode" not in st.session_state:
    st.session_state["barcode"] = ""

if "reset_barcode" not in st.session_state:
    st.session_state["reset_barcode"] = False

# --- Handle Resets Before Rendering Widgets ---
if st.session_state["reset_qty"]:
    st.session_state["quantity"] = 0
    st.session_state["reset_qty"] = False

if st.session_state["reset_barcode"]:
    st.session_state["barcode"] = ""
    st.session_state["reset_barcode"] = False

# --- App Title ---
st.title("📦 Inventory Count")

# --- Tabs for Scan View and Scanned Items ---
tab1, tab2 = st.tabs(["🔍 Scan", "📋 Scanned Items"])

with tab1:
    # --- Session Tools: Download and Reset ---
    st.subheader("Session Tools")
    col1, col2 = st.columns([1, 1])

    with col1:
        st.download_button(
            label="⬇️ Download My Count File",
            data=get_excel_download(df),
            file_name="my_inventory_count.xlsx",
            mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )

    with col2:
        reset_confirm = st.checkbox("Confirm reset?")
        if st.button("🗑️ Reset Count File") and reset_confirm:
            df = pd.DataFrame(columns=["SKU", "Counted Qty"])
            df.to_excel(XLSX_FILE, index=False)
            st.success("✅ Count file has been cleared.")
            time.sleep(1.5)
            st.rerun()

    # --- Scan Form ---
    with st.form("scan_form"):
        entry = st.text_input("Scan or Enter Barcode or SKU", max_chars=50, key="barcode")
        quantity = st.number_input("Quantity", min_value=0, step=1, key="quantity")
        submitted = st.form_submit_button("Add to Count")

    # --- Handle Submission (only if quantity > 0) ---
    if submitted and entry and st.session_state["quantity"] > 0:
        entry = entry.strip().replace(".0", "")
        name = None
        sku = None

        if entry in lookup_df.index:
            sku = str(lookup_df.at[entry, "SKU"])
            name = lookup_df.at[entry, "BRAND-NAME"]
        elif entry in lookup_by_sku.index:
            sku = entry
            name = lookup_by_sku.at[entry, "BRAND-NAME"]
        else:
            st.error("❌ Entry not found as Barcode or SKU in lookup file.")

        if sku:
            qty = st.session_state["quantity"]
            if sku in df["SKU"].values:
                idx = df[df["SKU"] == sku].index[0]
                df.at[idx, "Counted Qty"] += qty
                msg = f"✅ {qty} units of **{name}** added. Running total: **{df.at[idx, 'Counted Qty']}**."
            else:
                df = pd.concat([df, pd.DataFrame([{"SKU": sku, "Counted Qty": qty}])], ignore_index=True)
                msg = f"✅ {qty} units of **{name}** added to the list."

            df.to_excel(XLSX_FILE, index=False)
            st.success(msg)

            components.html("""<audio autoplay><source src='https://www.soundjay.com/buttons/sounds/beep-07.mp3' type='audio/mpeg'></audio>""", height=0)

            # Set reset flags
            st.session_state["reset_qty"] = True
            st.session_state["reset_barcode"] = True
            time.sleep(1.5)
            st.rerun()

    set_focus("barcode")

# --- Tab 2: Scanned Items View ---
with tab2:
    st.subheader("📋 Items Counted So Far")
    if not df.empty:
        st.dataframe(df.sort_values("SKU").reset_index(drop=True))
    else:
        st.info("No items have been scanned yet.")
