"use client";

import { useEffect, useState } from "react";

const plans = {
  budget: {
    label: "Student budget",
    price: "From R350 / week",
    items: ["Eggs", "Beans", "Rice", "Cabbage", "Chicken portions"],
    note: "Built for campus kitchens, shared flats, and real-life budgets.",
  },
  working: {
    label: "Working week",
    price: "10 packed lunches",
    items: ["Chicken breast", "Sweet potato", "Spinach", "Greek yoghurt", "Fruit"],
    note: "Cook once on Sunday. Keep your week moving between meetings.",
  },
  bulk: {
    label: "Lean bulk",
    price: "High-protein surplus",
    items: ["Lean mince", "Oats", "Eggs", "Peanut butter", "Milk"],
    note: "More fuel for stronger sessions, without losing the structure.",
  },
};

const modes = {
  train: {
    kicker: "Train",
    title: "Make every session count.",
    body: "Log workouts, HYROX stations, runs, and the small wins that turn into real momentum.",
    stats: ["04 workouts", "+18% progress", "07 day streak"],
  },
  fuel: {
    kicker: "Fuel",
    title: "Eat for the life you actually live.",
    body: "Track meals and macros, build South African grocery plans, and stay consistent on a budget.",
    stats: ["12 meals logged", "42g protein", "R350 weekly plan"],
  },
  connect: {
    kicker: "Connect",
    title: "Your people make the difference.",
    body: "Share the work, find your circle, and keep showing up with a community that gets the journey.",
    stats: ["1.2k local members", "24 comments", "∞ encouragement"],
  },
};

export default function Home() {
  const [mode, setMode] = useState<keyof typeof modes>("train");
  const [plan, setPlan] = useState<keyof typeof plans>("budget");
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => entries.forEach((entry) => entry.isIntersecting && entry.target.classList.add("is-visible")),
      { threshold: 0.12 },
    );
    document.querySelectorAll(".reveal").forEach((element) => observer.observe(element));
    return () => observer.disconnect();
  }, []);

  const activeMode = modes[mode];
  const activePlan = plans[plan];

  return (
    <main>
      <nav className="nav shell">
        <a className="brand" href="#top" aria-label="FitSocial home"><span>Fit</span>Social</a>
        <button className="menu-button" onClick={() => setMenuOpen(!menuOpen)} aria-label="Toggle menu">☰</button>
        <div className={`nav-links ${menuOpen ? "open" : ""}`}>
          <a href="#how-it-works">How it works</a>
          <a href="#plans">Meal plans</a>
          <a href="#community">Community</a>
          <a className="nav-cta" href="#download">Join the movement <span>↗</span></a>
        </div>
      </nav>

      <section className="hero shell" id="top">
        <div className="hero-copy reveal">
          <p className="eyebrow"><span className="eyebrow-dot" /> Built for South Africa</p>
          <h1>Your strongest routine starts <em>together.</em></h1>
          <p className="hero-sub">FitSocial brings training, nutrition, and community into one rhythm built for South Africa.</p>
          <div className="hero-actions">
            <a className="button button-primary" href="#download">Start your journey <span>↗</span></a>
            <a className="text-link" href="#how-it-works">See how it works <span>↓</span></a>
          </div>
          <div className="hero-proof"><div className="avatar-stack"><i>TN</i><i>LM</i><i>SK</i><i>+1k</i></div><span>South Africans building better habits together</span></div>
        </div>
        <div className="hero-visual reveal">
          <div className="hero-orbit orbit-one" /><div className="hero-orbit orbit-two" />
          <div className="hero-image"><img src="/og.png" alt="FitSocial athlete training in a modern gym" /></div>
          <div className="floating-card card-progress"><span className="mini-label">This week</span><strong>04 workouts</strong><small>+18% from last week</small><div className="mini-bars"><b /><b /><b /><b /><b /><b /><b /></div></div>
          <div className="floating-card card-community"><span className="pulse-icon">✦</span><div><strong>New circle unlocked</strong><small>HYROX crew • 24 members</small></div></div>
        </div>
      </section>

      <div className="location-strip"><div className="location-track"><span>South Africa</span><b>✦</b><span>Johannesburg</span><b>✦</b><span>Cape Town</span><b>✦</b><span>Pretoria</span><b>✦</b><span>Gqeberha</span><b>✦</b><span>Everywhere</span><b>✦</b><span>South Africa</span><b>✦</b><span>Johannesburg</span><b>✦</b><span>Cape Town</span></div></div>

      <section className="section shell reveal" id="how-it-works">
        <div className="section-heading"><p className="eyebrow">One app. One daily loop.</p><h2>Train with intention.<br /><em>Fuel with confidence.</em></h2><p>Consistency is not a personality trait. It is a system you can return to.</p></div>
        <div className="mode-layout">
          <div className="mode-tabs" role="tablist" aria-label="FitSocial pillars">
            {(Object.keys(modes) as Array<keyof typeof modes>).map((key, index) => <button key={key} className={mode === key ? "active" : ""} onClick={() => setMode(key)} role="tab" aria-selected={mode === key}><span>0{index + 1}</span>{modes[key].kicker}</button>)}
          </div>
          <div className="mode-panel">
            <div className="mode-content"><p className="eyebrow">{activeMode.kicker}</p><h3>{activeMode.title}</h3><p>{activeMode.body}</p><a className="text-link" href="#download">Explore {activeMode.kicker.toLowerCase()} <span>↗</span></a></div>
            <div className="mode-stats">{activeMode.stats.map((stat, index) => <div className="mode-stat" key={stat}><span>0{index + 1}</span><strong>{stat}</strong></div>)}</div>
          </div>
        </div>
      </section>

      <section className="split-section" id="community"><div className="split-image"><img src="/og.png" alt="FitSocial community training" /></div><div className="split-copy reveal"><p className="eyebrow">Built for the circle</p><h2>Progress feels different when your people <em>see it.</em></h2><p>From your first 5K to your next HYROX station, FitSocial turns private effort into shared momentum.</p><div className="quote-card"><span>“</span><p>It is easier to show up when the whole group is showing up too.</p><small>— Lunga, South Africa</small></div></div></section>

      <section className="section shell reveal" id="plans"><div className="section-heading compact"><p className="eyebrow">Fuel without the guesswork</p><h2>Plans that fit your <em>real life.</em></h2><p>Choose your rhythm. Get a grocery list, a prep flow, and a reason to keep going.</p></div><div className="plan-switcher"><div className="plan-buttons">{(Object.keys(plans) as Array<keyof typeof plans>).map((key) => <button key={key} className={plan === key ? "active" : ""} onClick={() => setPlan(key)}>{plans[key].label}</button>)}</div><div className="plan-card"><div className="plan-card-header"><div><p className="eyebrow">{activePlan.label}</p><h3>{activePlan.price}</h3></div><span className="plan-ring">✓</span></div><p>{activePlan.note}</p><div className="grocery-grid">{activePlan.items.map((item) => <span key={item}>+ {item}</span>)}</div><a className="button button-primary" href="#download">Build this plan <span>↗</span></a></div></div></section>

      <section className="loop-section shell reveal"><div className="loop-intro"><p className="eyebrow">The FitSocial loop</p><h2>Small actions.<br /><em>Stronger identity.</em></h2></div><div className="loop-steps"><div className="loop-line" /><article><span>01</span><strong>Log</strong><p>Capture the workout while the win is fresh.</p></article><article><span>02</span><strong>Fuel</strong><p>Make the next meal support the next session.</p></article><article><span>03</span><strong>Share</strong><p>Let your circle turn effort into momentum.</p></article><article><span>04</span><strong>Repeat</strong><p>Come back tomorrow with more confidence.</p></article></div></section>

      <section className="download-section shell" id="download"><div className="download-card reveal"><div><p className="eyebrow">Made in South Africa. Made for your next level.</p><h2>Ready to make consistency <em>your thing?</em></h2><p>Join the FitSocial movement and start building a routine that can travel with you—from weekday mornings to every finish line after.</p></div><div className="download-actions"><a className="button button-light" href="mailto:hello@fitsocial.app">Get early access <span>↗</span></a><small>No pressure. Just progress.</small></div></div></section>
      <footer className="footer shell"><a className="brand" href="#top"><span>Fit</span>Social</a><span>Train. Fuel. Share. Grow.</span><span>© 2026 FitSocial</span></footer>
    </main>
  );
}
