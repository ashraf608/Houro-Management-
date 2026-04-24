import { useEffect, useMemo, useState } from "react";

const STORAGE_KEY = "houro-logistik-pro-data";

export default function App() {
  const [tab, setTab] = useState("dashboard");
  const [search, setSearch] = useState("");

  const [data, setData] = useState<any>(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    return saved
      ? JSON.parse(saved)
      : { operations: [], expenses: [], invoices: [] };
  });

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  }, [data]);

  // ---------- ADD ----------
  const addOperation = () => {
    const company = prompt("Company");
    const revenue = Number(prompt("Revenue"));
    setData({
      ...data,
      operations: [{ id: Date.now(), company, revenue }, ...data.operations],
    });
  };

  const addExpense = () => {
    const title = prompt("Type");
    const amount = Number(prompt("Amount"));
    setData({
      ...data,
      expenses: [{ id: Date.now(), title, amount }, ...data.expenses],
    });
  };

  const addInvoice = () => {
    const company = prompt("Company");
    const total = Number(prompt("Total"));
    const paid = Number(prompt("Paid"));
    setData({
      ...data,
      invoices: [{ id: Date.now(), company, total, paid }, ...data.invoices],
    });
  };

  // ---------- DELETE ----------
  const remove = (type: string, id: number) => {
    setData({
      ...data,
      [type]: data[type].filter((x: any) => x.id !== id),
    });
  };

  // ---------- EDIT ----------
  const edit = (type: string, item: any) => {
    const updated = { ...item };

    Object.keys(item).forEach((key) => {
      if (key !== "id") {
        const val = prompt(`Edit ${key}`, item[key]);
        if (val !== null) updated[key] = isNaN(Number(val)) ? val : Number(val);
      }
    });

    setData({
      ...data,
      [type]: data[type].map((x: any) => (x.id === item.id ? updated : x)),
    });
  };

  // ---------- SEARCH ----------
  const filter = (arr: any[]) => {
    return arr.filter((x) =>
      JSON.stringify(x).toLowerCase().includes(search.toLowerCase())
    );
  };

  // ---------- BACKUP ----------
  const backup = () => {
    const blob = new Blob([JSON.stringify(data, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "houro-backup.json";
    a.click();
  };

  // ---------- STATS ----------
  const stats = useMemo(() => {
    const revenue = data.operations.reduce(
      (s: number, o: any) => s + (o.revenue || 0),
      0
    );
    const expenses = data.expenses.reduce(
      (s: number, e: any) => s + (e.amount || 0),
      0
    );
    const invoices = data.invoices.reduce(
      (s: number, i: any) => s + (i.total || 0),
      0
    );
    const paid = data.invoices.reduce(
      (s: number, i: any) => s + (i.paid || 0),
      0
    );

    return {
      revenue,
      expenses,
      profit: revenue + paid - expenses,
      open: invoices - paid,
    };
  }, [data]);

  return (
    <div style={{ padding: 20, fontFamily: "Arial" }}>
      <h1>Houro Logistik Pro</h1>

      {/* Search + Backup */}
      <div style={{ marginBottom: 10 }}>
        <input
          placeholder="Search..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button onClick={backup}>Download Backup</button>
      </div>

      {/* NAV */}
      <div>
        <button onClick={() => setTab("dashboard")}>Dashboard</button>
        <button onClick={() => setTab("operations")}>Operations</button>
        <button onClick={() => setTab("expenses")}>Expenses</button>
        <button onClick={() => setTab("invoices")}>Invoices</button>
      </div>

      {/* DASHBOARD */}
      {tab === "dashboard" && (
        <div>
          <h2>Dashboard</h2>
          <p>Revenue: {stats.revenue}</p>
          <p>Expenses: {stats.expenses}</p>
          <p>Profit: {stats.profit}</p>
          <p>Open Invoices: {stats.open}</p>
        </div>
      )}

      {/* OPERATIONS */}
      {tab === "operations" && (
        <div>
          <h2>Operations</h2>
          <button onClick={addOperation}>Add</button>

          {filter(data.operations).map((o: any) => (
            <div key={o.id}>
              {o.company} | {o.revenue}
              <button onClick={() => edit("operations", o)}>Edit</button>
              <button onClick={() => remove("operations", o.id)}>Delete</button>
            </div>
          ))}
        </div>
      )}

      {/* EXPENSES */}
      {tab === "expenses" && (
        <div>
          <h2>Expenses</h2>
          <button onClick={addExpense}>Add</button>

          {filter(data.expenses).map((e: any) => (
            <div key={e.id}>
              {e.title} | {e.amount}
              <button onClick={() => edit("expenses", e)}>Edit</button>
              <button onClick={() => remove("expenses", e.id)}>Delete</button>
            </div>
          ))}
        </div>
      )}

      {/* INVOICES */}
      {tab === "invoices" && (
        <div>
          <h2>Invoices</h2>
          <button onClick={addInvoice}>Add</button>

          {filter(data.invoices).map((i: any) => (
            <div key={i.id}>
              {i.company} | {i.total} | {i.paid}
              <button onClick={() => edit("invoices", i)}>Edit</button>
              <button onClick={() => remove("invoices", i.id)}>Delete</button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
