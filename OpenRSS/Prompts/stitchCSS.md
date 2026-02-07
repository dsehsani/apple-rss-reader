<!DOCTYPE html>

<html class="dark" lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>Today Feed - RSS Reader</title>
<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries"></script>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<script id="tailwind-config">
        tailwind.config = {
            darkMode: "class",
            theme: {
                extend: {
                    colors: {
                        "primary": "#137cec",
                        "background-light": "#f6f7f8",
                        "background-dark": "#000000",
                    },
                    fontFamily: {
                        "display": ["Inter", "sans-serif"]
                    },
                    borderRadius: {
                        "DEFAULT": "0.5rem",
                        "lg": "1rem",
                        "xl": "1.5rem",
                        "full": "9999px"
                    },
                },
            },
        }
    </script>
<style>
        .liquid-glass {
            background: rgba(255, 255, 255, 0.05);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        .liquid-glass-header {
            background: rgba(0, 0, 0, 0.7);
            backdrop-filter: blur(15px);
            -webkit-backdrop-filter: blur(15px);
            border-bottom: 0.5px solid rgba(255, 255, 255, 0.1);
        }
        .liquid-glass-tab {
            background: rgba(16, 25, 34, 0.8);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border-top: 0.5px solid rgba(255, 255, 255, 0.1);
        }
    </style>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="bg-background-light dark:bg-background-dark font-display text-white selection:bg-primary/30">
<!-- Sticky Navigation Bar -->
<header class="sticky top-0 z-50 liquid-glass-header pb-2">
<div class="flex flex-col gap-2 p-4">
<div class="flex items-center h-12 justify-between">
<div class="flex items-center justify-center size-10 rounded-full hover:bg-white/10 transition-colors cursor-pointer">
<span class="material-symbols-outlined text-white text-[24px]">search</span>
</div>
<div class="flex w-12 items-center justify-end">
<button class="flex size-10 items-center justify-center rounded-full hover:bg-white/10 transition-colors cursor-pointer">
<span class="material-symbols-outlined text-white text-[24px]">tune</span>
</button>
</div>
</div>
<p class="text-white tracking-tight text-[34px] font-bold leading-tight px-1">Today</p>
</div>
<!-- Horizontal Filter Chips -->
<div class="flex gap-2 px-4 py-2 overflow-x-auto no-scrollbar">
<div class="flex h-9 shrink-0 items-center justify-center gap-x-2 rounded-full bg-primary px-5 transition-all">
<p class="text-white text-sm font-semibold leading-normal">All Updates</p>
</div>
<div class="flex h-9 shrink-0 items-center justify-center gap-x-2 rounded-full liquid-glass px-5 hover:bg-white/10 transition-all cursor-pointer">
<p class="text-white/90 text-sm font-medium leading-normal">Design</p>
</div>
<div class="flex h-9 shrink-0 items-center justify-center gap-x-2 rounded-full liquid-glass px-5 hover:bg-white/10 transition-all cursor-pointer">
<p class="text-white/90 text-sm font-medium leading-normal">Tech News</p>
</div>
<div class="flex h-9 shrink-0 items-center justify-center gap-x-2 rounded-full liquid-glass px-5 hover:bg-white/10 transition-all cursor-pointer">
<p class="text-white/90 text-sm font-medium leading-normal">Work</p>
</div>
<div class="flex h-9 shrink-0 items-center justify-center gap-x-2 rounded-full liquid-glass px-5 hover:bg-white/10 transition-all cursor-pointer">
<p class="text-white/90 text-sm font-medium leading-normal">Productivity</p>
</div>
</div>
</header>
<main class="flex flex-col gap-6 p-4 pb-32">
<!-- Article Card 1 -->
<div class="group @container">
<div class="flex flex-col items-stretch justify-start rounded-xl overflow-hidden bg-[#1c2127] border border-white/5 shadow-xl active:scale-[0.98] transition-transform duration-200">
<div class="w-full bg-center bg-no-repeat aspect-video bg-cover" data-alt="Modern smartphone showing local AI processing interface" style='background-image: url("https://lh3.googleusercontent.com/aida-public/AB6AXuDGwGT929lb7Zza5rOOLkGhNlTlmQJ2GNRXDw4ReaYjMuPuNcuyL5fIs4dTjzNok9fITF2mLk1ihGy589rZpP5qHsLxxdEvWQfUcbTru3jyxTVNLHe8-gsFMBGSswHySaSpbETGl4I3R6XGZrAf3iOWh9UkCrgLu-cjOT5csVFGes3wfjLFrhiz7MR1t0nS5YIfKUwf8WwE6-WwZnd0MeiyD__HZSua41PeQTFDkLcHlRmH_SGU3rRfKKkAd4UsZYy7zyslqs6Tpg");'>
</div>
<div class="flex w-full min-w-72 grow flex-col items-stretch justify-center gap-2 p-4">
<div class="flex items-center gap-2">
<div class="size-5 rounded bg-primary/20 flex items-center justify-center">
<span class="material-symbols-outlined text-primary text-[14px]">bolt</span>
</div>
<p class="text-[#9daab9] text-xs font-medium uppercase tracking-wider">TechCrunch • 2h ago</p>
</div>
<p class="text-white text-xl font-bold leading-tight tracking-tight group-hover:text-primary transition-colors">The Future of AI is Local</p>
<p class="text-[#9daab9] text-sm font-normal leading-relaxed line-clamp-2">Privacy-focused on-device processing is becoming the new standard for modern mobile applications. Large language models are shrinking to fit your pocket.</p>
<div class="flex items-center justify-between mt-2 pt-2 border-t border-white/5">
<div class="flex gap-3">
<span class="material-symbols-outlined text-[#9daab9] text-[20px] cursor-pointer hover:text-white">bookmark</span>
<span class="material-symbols-outlined text-[#9daab9] text-[20px] cursor-pointer hover:text-white">share</span>
</div>
<button class="flex items-center justify-center rounded-lg h-8 px-4 bg-primary/10 text-primary text-sm font-semibold hover:bg-primary hover:text-white transition-all">
<span>Read More</span>
</button>
</div>
</div>
</div>
</div>
<!-- Article Card 2 -->
<div class="group @container">
<div class="flex flex-col items-stretch justify-start rounded-xl overflow-hidden bg-[#1c2127] border border-white/5 shadow-xl active:scale-[0.98] transition-transform duration-200">
<div class="w-full bg-center bg-no-repeat aspect-video bg-cover" data-alt="Abstract translucent glass textures with soft blurs" style='background-image: url("https://lh3.googleusercontent.com/aida-public/AB6AXuBVx1c0Wp9QX6s9hroCIMwG4zH2gAJcnzXWqt41cR-27Tfnxu0zYaXcz4W-TT6ESAbngjAEauvIFc6OyKNhYb5-jTFeaX0oDTlkNr83tPXzZq7Al5XenzKQAQ6SLMf0kJCXUwyJ3zB2ZzCQIL2MHpthlLsGZlicD_v2zENBikDySPkJQCYTkulBrs5ef6nnCw2ybJNBtBjoW9VIdMKQovX0sa5FcGRCkKweHjSJ_Wsj1z5u6SiEPI1WB-rTyPwqWv2loNK2M3spPA");'>
</div>
<div class="flex w-full min-w-72 grow flex-col items-stretch justify-center gap-2 p-4">
<div class="flex items-center gap-2">
<div class="size-5 rounded bg-orange-500/20 flex items-center justify-center">
<span class="material-symbols-outlined text-orange-500 text-[14px]">brush</span>
</div>
<p class="text-[#9daab9] text-xs font-medium uppercase tracking-wider">Smashing Magazine • 5h ago</p>
</div>
<p class="text-white text-xl font-bold leading-tight tracking-tight group-hover:text-primary transition-colors">Mastering Liquid Glass Effects</p>
<p class="text-[#9daab9] text-sm font-normal leading-relaxed line-clamp-2">How to achieve perfect translucency and background blurs in your next mobile project using system APIs and modern CSS techniques.</p>
<div class="flex items-center justify-between mt-2 pt-2 border-t border-white/5">
<div class="flex gap-3">
<span class="material-symbols-outlined text-[#9daab9] text-[20px] cursor-pointer hover:text-white">bookmark</span>
<span class="material-symbols-outlined text-[#9daab9] text-[20px] cursor-pointer hover:text-white">share</span>
</div>
<button class="flex items-center justify-center rounded-lg h-8 px-4 bg-primary/10 text-primary text-sm font-semibold hover:bg-primary hover:text-white transition-all">
<span>Read More</span>
</button>
</div>
</div>
</div>
</div>
<!-- Article Card 3 -->
<div class="group @container">
<div class="flex flex-col items-stretch justify-start rounded-xl overflow-hidden bg-[#1c2127] border border-white/5 shadow-xl active:scale-[0.98] transition-transform duration-200">
<div class="w-full bg-center bg-no-repeat aspect-video bg-cover" data-alt="Clean minimalist workspace with a laptop and a plant" style='background-image: url("https://lh3.googleusercontent.com/aida-public/AB6AXuDRZOy4E90R9gmDzIDXYz6-8n83zEZuL6Zvif2ZDhTCgbEGnbr8KNTVTpbSCMWvobVe0xtts51miGiTyJCcME0CY9u5GlWj_1QGemTYx3N3b432l2B3KPGWX_NAMwzzLqENBuJ1Ss_ner-wO9Q2cf8D8u0xRmecvcOKkWuJ8lctoWHdhBg-SSd6JkPlm36dI1a6cm88l3q8aaTDILBJO6T_zkdcDC4WhiD40yeZzYO9FZJ4ve-SAq8nOzBZeajhId70dOy1ZK3P5Q");'>
</div>
<div class="flex w-full min-w-72 grow flex-col items-stretch justify-center gap-2 p-4">
<div class="flex items-center gap-2">
<div class="size-5 rounded bg-green-500/20 flex items-center justify-center">
<span class="material-symbols-outlined text-green-500 text-[14px]">chair</span>
</div>
<p class="text-[#9daab9] text-xs font-medium uppercase tracking-wider">Work Life • 8h ago</p>
</div>
<p class="text-white text-xl font-bold leading-tight tracking-tight group-hover:text-primary transition-colors">The Rise of Minimalist Workspaces</p>
<p class="text-[#9daab9] text-sm font-normal leading-relaxed line-clamp-2">Exploring how physical environment impacts digital productivity and the tools that bridge the gap between office and home.</p>
<div class="flex items-center justify-between mt-2 pt-2 border-t border-white/5">
<div class="flex gap-3">
<span class="material-symbols-outlined text-[#9daab9] text-[20px] cursor-pointer hover:text-white">bookmark</span>
<span class="material-symbols-outlined text-[#9daab9] text-[20px] cursor-pointer hover:text-white">share</span>
</div>
<button class="flex items-center justify-center rounded-lg h-8 px-4 bg-primary/10 text-primary text-sm font-semibold hover:bg-primary hover:text-white transition-all">
<span>Read More</span>
</button>
</div>
</div>
</div>
</div>
</main>
<!-- Bottom Tab Bar -->
<nav class="fixed bottom-0 left-0 right-0 z-[100] liquid-glass-tab px-6 pb-8 pt-3">
<div class="max-w-md mx-auto flex items-center justify-between">
<div class="flex flex-col items-center gap-1 group cursor-pointer">
<span class="material-symbols-outlined text-primary text-[28px] font-variation-fill-1">article</span>
<span class="text-[10px] font-bold text-primary">Today</span>
</div>
<div class="flex flex-col items-center gap-1 group cursor-pointer opacity-50 hover:opacity-100 transition-opacity">
<span class="material-symbols-outlined text-white text-[28px]">explore</span>
<span class="text-[10px] font-medium text-white">Discover</span>
</div>
<div class="flex flex-col items-center gap-1 group cursor-pointer opacity-50 hover:opacity-100 transition-opacity">
<span class="material-symbols-outlined text-white text-[28px]">bookmarks</span>
<span class="text-[10px] font-medium text-white">Saved</span>
</div>
<div class="flex flex-col items-center gap-1 group cursor-pointer opacity-50 hover:opacity-100 transition-opacity">
<span class="material-symbols-outlined text-white text-[28px]">rss_feed</span>
<span class="text-[10px] font-medium text-white">Sources</span>
</div>
<div class="flex flex-col items-center gap-1 group cursor-pointer opacity-50 hover:opacity-100 transition-opacity">
<span class="material-symbols-outlined text-white text-[28px]">settings</span>
<span class="text-[10px] font-medium text-white">Settings</span>
</div>
</div>
</nav>
</body></html>
