import React from 'react';
import { 
  ArrowUpRight, 
  Brain, 
  Code2, 
  Shield, 
  Sparkles, 
  Waves, 
  Activity, 
  Search,
  Anchor
} from "lucide-react";

// --- Mock UI Components for the single-file demo ---
const Button = ({ className, variant, size, children, ...props }: any) => {
  const base = "inline-flex items-center justify-center rounded-full font-medium transition-all focus:outline-none disabled:opacity-50";
  const variants = {
    default: "bg-amber-400 text-slate-950 hover:bg-amber-300",
    outline: "border border-slate-700 bg-transparent hover:bg-slate-800 text-slate-200",
    ghost: "hover:bg-slate-800 text-slate-200",
  };
  const sizes = { sm: "h-9 px-4 text-xs", default: "h-11 px-8 text-sm", icon: "h-10 w-10" };
  return <button className={`${base} ${variants[variant || 'default']} ${sizes[size || 'default']} ${className}`} {...props}>{children}</button>;
};
const Badge = ({ className, children }: any) => <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold transition-colors ${className}`}>{children}</span>;
// --------------------------------------------------

export default function LandingPage() {
  return (
    <main className="relative min-h-screen w-full overflow-x-hidden bg-slate-950 text-slate-200 selection:bg-amber-500/30 font-sans">
      {/* --- Global Atmospheric Effects --- */}
      
      {/* 1. Grain/Noise Overlay */}
      <div className="pointer-events-none fixed inset-0 z-50 opacity-[0.03]" style={{ backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noiseFilter'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.65' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noiseFilter)'/%3E%3C/svg%3E")` }}></div>
      
      {/* 2. Deep Sea Glows (Fixed Background) */}
      <div className="pointer-events-none fixed inset-0 z-0">
        <div className="absolute top-[-10%] left-[-10%] h-[800px] w-[800px] rounded-full bg-slate-900/40 blur-[120px]" />
        <div className="absolute bottom-[-10%] right-[-10%] h-[600px] w-[600px] rounded-full bg-amber-900/10 blur-[100px]" />
        <div className="absolute top-[40%] left-[50%] h-[400px] w-[400px] -translate-x-1/2 rounded-full bg-sky-950/20 blur-[120px]" />
      </div>

      <div className="relative z-10">
        <HeroSection />
        <FeatureStrip />
        <HowItWorks />
        <ResolutionModes />
        <WhySection />
        <FooterDots />
      </div>
    </main>
  );
}

function HeroSection() {
  return (
    <section className="relative min-h-screen w-full overflow-hidden">
      {/* Background Image with heavy darkening */}
      <div className="absolute inset-0 z-0">
         <img
          src="/nereus_compress.gif"
          alt="Nereus Hero Animation"
          className="absolute inset-0 h-full w-full object-cover opacity-40 mix-blend-luminosity grayscale-[30%]"
        />
        {/* Vignette & Gradient Overlay */}
        <div className="absolute inset-0 bg-gradient-to-b from-slate-950/90 via-slate-950/60 to-slate-950" />
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,transparent_0%,#020617_100%)]" />
      </div>

      <div className="relative z-10 mx-auto flex min-h-screen max-w-7xl flex-col px-6 pt-6 md:px-10">
        {/* Navigation */}
        <header className="flex items-center justify-between py-6">
          <div className="group flex items-center gap-4 cursor-pointer">
            <div className="relative flex h-10 w-10 items-center justify-center rounded-full bg-slate-950 ring-1 ring-slate-800 transition-all duration-500 group-hover:ring-amber-500/50 group-hover:shadow-[0_0_20px_rgba(250,204,21,0.3)]">
               {/* Logo Placeholder */}
               <div className="h-5 w-5 rounded-sm bg-gradient-to-tr from-amber-600 to-amber-300" />
            </div>
            <div className="flex flex-col">
              <span className="font-serif text-lg tracking-widest text-slate-200 transition-colors group-hover:text-amber-100">NEREUS</span>
            </div>
          </div>

          <nav className="hidden items-center gap-8 md:flex">
            {['Features', 'Protocol', 'Resolution', 'FAQ'].map((item) => (
              <a key={item} href={`#${item.toLowerCase()}`} className="text-xs font-medium uppercase tracking-widest text-slate-500 transition-colors hover:text-amber-400">
                {item}
              </a>
            ))}
            <Button size="sm" className="bg-amber-500/10 text-amber-300 hover:bg-amber-500/20 border border-amber-500/20 backdrop-blur-md">
              <a href="/main" className="text-white flex items-center gap-2">
                Launch App <ArrowUpRight className="h-3 w-3" />
              </a>
            </Button>
          </nav>
        </header>

        {/* Main Hero Content */}
        <div className="mt-20 flex flex-1 flex-col items-center justify-center text-center md:mt-0">
          
          <div className="animate-fade-in-up space-y-8">
            <h1 className="max-w-4xl font-serif text-5xl text-slate-100 drop-shadow-2xl sm:text-7xl md:text-8xl">
              <span className="block opacity-90">Predict the</span>
              <span className="block bg-gradient-to-b from-amber-100 via-amber-300 to-amber-600 bg-clip-text text-transparent opacity-90">
                Unknowable
              </span>
            </h1>

            <p className="mx-auto max-w-xl text-sm leading-relaxed text-slate-400 md:text-base">
              Empower Your Visionary, Light Up the Pools of Possibility with the power of <p className='text-3xl italic text-white'>Nereus</p>
            </p>

            <div className="flex flex-col items-center justify-center gap-4 pt-4 sm:flex-row">
              <Button className="group h-12 min-w-[160px] rounded-sm bg-amber-500 px-8 text-slate-950 shadow-[0_0_40px_rgba(245,158,11,0.4)] transition-all hover:bg-amber-400 hover:shadow-[0_0_60px_rgba(245,158,11,0.6)]">
                <span className="font-semibold tracking-wide">Enter App</span>
              </Button>
              <Button variant="outline" className="h-12 min-w-[160px] rounded-sm border-slate-800 bg-slate-950/50 text-slate-400 backdrop-blur hover:border-amber-500/30 hover:text-amber-200">
                Read the Whitepaper
              </Button>
            </div>
          </div>
        </div>
        
        {/* Scroll Indicator */}
        <div className="absolute bottom-10 left-1/2 -translate-x-1/2 opacity-50">
           <div className="h-12 w-[1px] bg-gradient-to-b from-slate-700 to-transparent" />
        </div>
      </div>
    </section>
  );
}

function FeatureStrip() {
  const features = [
    {
      title: "User oriented Pools",
      description: "By providing instructions and liquidity, user gain governance of the world of Nereus.",
      icon: Sparkles,
    },
    {
      title: "Infinite Topics",
      description: "Anything that can be determined can be a potential market.",
      icon: Brain,
    },
    {
      title: "Immutable Resolution",
      description: "Via Nautilus, the Market resolves in Trustable, Immutable Code and Large Language Model.",
      icon: Code2,
    },
  ];

  return (
    <section id="features" className="relative py-32">
      <div className="mx-auto max-w-6xl px-6">
        <div className="grid gap-8 md:grid-cols-3">
          {features.map((f, i) => (
            <div
              key={f.title}
              className="group relative overflow-hidden rounded-sm border border-slate-800 bg-slate-900/20 p-8 backdrop-blur-sm transition-all duration-700 hover:bg-slate-900/40"
            >
              {/* Hover Glow Effect */}
              <div className="absolute -inset-1 rounded-sm bg-gradient-to-r from-amber-500/0 via-amber-500/10 to-amber-500/0 opacity-0 blur-xl transition-opacity duration-700 group-hover:opacity-100" />
              
              <div className="relative z-10 flex flex-col items-start gap-4">
                <div className="flex h-12 w-12 items-center justify-center rounded-full bg-slate-950 border border-slate-800 text-slate-400 shadow-2xl transition-colors group-hover:border-amber-500/40 group-hover:text-amber-400">
                  <f.icon className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="mb-2 font-serif text-xl text-slate-200 group-hover:text-amber-100">{f.title}</h3>
                  <p className="text-sm leading-relaxed text-slate-500 group-hover:text-slate-400">
                    {f.description}
                  </p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function HowItWorks() {
  const steps = [
    { title: "Initialization", body: "Define the question. Choose the oracle. Summon the pool." },
    { title: "Positions", body: "Traders buy outcomes. LPs seed depth. The curve adapts." },
    { title: "Settlement", body: "Reality is verified. Truth is pushed on-chain. Value settles." },
  ];

  return (
    <section className="relative border-y border-slate-900/50 bg-slate-950/50 py-32">
      <div className="mx-auto max-w-5xl px-6">
        <div className="mb-16 md:text-center">
          <h2 className="font-serif text-3xl text-slate-200 md:text-4xl">
            Protocol <span className="text-amber-500">Mechanics</span>
          </h2>
        </div>

        <div className="relative grid gap-12 md:grid-cols-3">
          {/* Connecting Line (Desktop) */}
          <div className="absolute left-0 top-1/2 hidden h-[1px] w-full -translate-y-1/2 bg-gradient-to-r from-transparent via-amber-500/30 to-transparent md:block" />

          {steps.map((s, idx) => (
            <div key={idx} className="relative flex flex-col items-center text-center">
              {/* Number Node */}
              <div className="relative mb-6 flex h-16 w-16 items-center justify-center rounded-full border border-slate-800 bg-slate-950 shadow-[0_0_30px_rgba(0,0,0,0.5)] z-10 transition-transform duration-500 hover:scale-110 hover:border-amber-500/50">
                <span className="font-serif text-xl text-slate-400">{idx + 1}</span>
                {/* Ping animation */}
                <div className="absolute inset-0 -z-10 animate-ping rounded-full bg-amber-500/10 opacity-20" style={{ animationDelay: `${idx * 0.5}s` }} />
              </div>

              <h3 className="mb-2 text-lg font-medium text-slate-200">{s.title}</h3>
              <p className="text-sm text-slate-500">{s.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function ResolutionModes() {
  return (
    <section className="relative py-32">
      {/* We use flex-row-reverse to keep the card on the left and the text on the right (order 2) on large screens */}
      <div className="mx-auto flex max-w-6xl flex-col gap-16 px-6 md:flex-row md:items-center">
        
        {/* Card Block - Left Aligned on Desktop */}
        <div className="md:w-1/2">
           {/* Abstract "Hologram" Card */}
           <div className="relative rounded-2xl border border-slate-800 bg-slate-950/80 p-1">
              <div className="absolute -inset-px bg-gradient-to-b from-emerald-500/20 to-transparent opacity-20 blur-lg" />
              
              <div className="relative grid gap-4 overflow-hidden rounded-xl bg-slate-950 p-6">
                  {/* Mode 1 */}
                  <div className="flex items-start gap-4 rounded-lg border border-slate-800/50 bg-slate-900/20 p-4 transition-colors hover:border-amber-500/30 hover:bg-slate-900/40">
                     <div className="mt-1 text-amber-500">
                        <Brain className="h-5 w-5" />
                     </div>
                     <div>
                        <h4 className="text-sm font-medium text-slate-200">AI Agents</h4>
                        <p className="text-xs text-slate-500 mt-1">LLMs parse news & APIs to resolve markets instantly.</p>
                     </div>
                  </div>

                  {/* Mode 2 */}
                  <div className="flex items-start gap-4 rounded-lg border border-slate-800/50 bg-slate-900/20 p-4 transition-colors hover:border-emerald-500/30 hover:bg-slate-900/40">
                     <div className="mt-1 text-emerald-500">
                        <Code2 className="h-5 w-5" />
                     </div>
                     <div>
                        <h4 className="text-sm font-medium text-slate-200">On-Chain Code</h4>
                        <p className="text-xs text-slate-500 mt-1">Smart contracts resolve based on price feeds & events.</p>
                     </div>
                  </div>
              </div>
           </div>
        </div>

        {/* Text Block - Right Aligned on Desktop */}
        <div className="md:w-1/2 space-y-6 md:text-right">
          {/* Badge: Use `md:ml-auto` to push the badge to the right in the text-right container */}
          <h2 className="font-serif text-4xl text-slate-100">
            Trust is <br/>
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-emerald-200 to-emerald-600">
              Deterministic
            </span>
          </h2>
          {/* Paragraph: Use `md:ml-auto` to push a fixed-width paragraph to the right in the text-right container */}
          <p className="max-w-md text-slate-400 leading-relaxed md:ml-auto">
            Nereus allows creators to mix resolution engines. AI agents read unstructured data. Code checks on-chain state. Humans intervene only as a failsafe.
          </p>
        </div>
      </div>
    </section>
  );
}

function WhySection() {
  return (
    <section className="relative border-t border-slate-900 bg-slate-950 py-32">
      {/* Background Accent */}
      <div className="absolute right-0 top-0 h-[500px] w-[500px] bg-[radial-gradient(circle_at_center,rgba(251,191,36,0.03),transparent_70%)] pointer-events-none" />

      <div className="mx-auto flex max-w-6xl flex-col gap-12 px-6 lg:flex-row">
        <div className="lg:w-1/3 space-y-6">
          <h2 className="font-serif text-3xl text-slate-100">
            Depth where it <br />
            <span className="italic text-amber-500">matters.</span>
          </h2>
          <p className="text-sm text-slate-400">
            Orderbooks fragment liquidity. Nereus uses concentrated pools and cross-market collateral to create deep oceans of liquidity around the current consensus.
          </p>
        </div>

        <div className="grid flex-1 gap-6 sm:grid-cols-2 lg:w-2/3">
          <MiniMetric
            icon={Waves}
            label="Continuous Liquidity"
            value="LMSR curves ensure there is always a price for your position."
          />
          <MiniMetric
            icon={Sparkles}
            label="Yield Bearing"
            value="Collateral is never idle. Earn external yield while you bet."
          />
          <MiniMetric
            icon={Activity}
            label="Latency Tolerant"
            value="Architected for L2 finality and delayed oracle reporting."
          />
          <MiniMetric
            icon={Shield}
            label="Circuit Breakers"
            value="Automated pause states during high volatility events."
          />
        </div>
      </div>
    </section>
  );
}

// --- The Requested Component (Updated for darker theme) ---
function MiniMetric({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof Waves;
  label: string;
  value: string;
}) {
  return (
    <div className="group relative w-full rounded-2xl sm:w-auto">
      {/* 1. The Initial Border (TL to BR) - Fades OUT on hover */}
      {/* Changed colors to be more subtle/mysterious (amber-900/amber-600) */}
      <div className="absolute -inset-px rounded-2xl bg-gradient-to-br from-amber-600/30 via-transparent to-amber-600/30 transition-opacity duration-500 group-hover:opacity-0" />

      {/* 2. The Hover Border (TR to BL) - Fades IN on hover */}
      {/* Brighter amber on hover */}
      <div className="absolute -inset-px rounded-2xl bg-gradient-to-bl from-amber-400/50 via-transparent to-amber-400/50 opacity-0 transition-opacity duration-500 group-hover:opacity-100" />

      {/* 3. The Main Content */}
      <div className="relative h-full flex flex-col gap-4 rounded-2xl bg-slate-950 p-6 shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)]">
        {/* Subtle inner noise/texture */}
        <div className="absolute inset-0 rounded-2xl bg-[radial-gradient(circle_at_50%_0%,rgba(255,255,255,0.03),transparent_70%)] pointer-events-none" />
        
        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-900 text-amber-500/80 shadow-inner ring-1 ring-slate-800 group-hover:text-amber-400 group-hover:shadow-[0_0_15px_rgba(245,158,11,0.2)] transition-all">
          <Icon className="h-5 w-5" />
        </div>
        
        <div className="relative">
          <div className="font-serif text-lg text-slate-200 group-hover:text-amber-50 transition-colors">{label}</div>
          <p className="mt-2 text-xs leading-relaxed text-slate-500 group-hover:text-slate-400 transition-colors">{value}</p>
        </div>
      </div>
    </div>
  );
}

function FooterDots() {
  return (
    <footer className="bg-slate-950 py-12">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 opacity-30 transition-opacity hover:opacity-100">
        <span className="font-serif text-xs tracking-widest text-slate-500">
          NEREUS PROTOCOL © {new Date().getFullYear()}
        </span>
        <div className="flex items-center gap-4">
          <Anchor className="h-4 w-4 text-slate-600" />
        </div>
      </div>
    </footer>
  );
}