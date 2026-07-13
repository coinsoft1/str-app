// lib/services/app_categorization.dart
class AppCategorization {
  // Comprehensive Education Apps
  static const Set<String> educationApps = {
    // Learning Platforms
    'org.khanacademy.android', // Khan Academy
    'com.duolingo', // Duolingo
    'com.busuu.android.enc', // Busuu
    'com.babbel.mobile.android.en', // Babbel
    'com.rosettastone.mobile.android', // Rosetta Stone
    'com.memrise.android', // Memrise
    'com.dropbox.android', // Dropbox (homework files)
    'com.google.android.apps.docs.editors.docs', // Google Docs
    'com.google.android.apps.docs.editors.sheets', // Google Sheets
    'com.google.android.apps.docs.editors.slides', // Google Slides
    'com.microsoft.office.word', // Microsoft Word
    'com.microsoft.office.excel', // Microsoft Excel
    'com.microsoft.office.powerpoint', // PowerPoint
    'com.google.android.apps.classroom', // Google Classroom
    'com.blackboard.android', // Blackboard
    'com.instructure.candroid', // Canvas
    'com.moodle.moodlemobile', // Moodle
    'com.zoom.us', // Zoom (classes)
    'com.microsoft.teams', // Teams (classes)
    'com.google.android.apps.meetings', // Google Meet
    'com.webex.meetings', // WebEx
    'com.gotomeeting', // GoToMeeting
    
    // STEM & Coding
    'com.lightbot.lightbot', // LightBot
    'com.thunkable.android.jasonmkinney.hcui0b59722646b11e8911c0b2287a5b7', // MIT App Inventor
    'com.scratch.scratch', // Scratch
    'com.tynker.Tynker', // Tynker
    'com.gethopscotch.hopscotch', // Hopscotch
    'com.sololearn', // SoloLearn
    'com.udemy.android', // Udemy
    'com.coursera.android', // Coursera
    'com.edx.mobile', // edX
    'com.kodable', // Kodable
    'com.daisythedinolwc', // Daisy the Dinosaur
    'com.sphero.sprk', // Sphero Edu
    
    // Math
    'com.photomath', // Photomath
    'com.google.android.calculator', // Calculator
    'com.microsoft.math', // Microsoft Math
    'com.mathway.mathway', // Mathway
    'com.symbo1ab.brag', // Symbolab
    'com.geogebra.android', // GeoGebra
    'com.duckduckmoose.kindergarten', // Duck Duck Moose Math
    'com.scratchworks.mentalmath', // Mental Math
    
    // Reading & Languages
    'com.amazon.kindle', // Kindle
    'com.google.android.apps.books', // Google Play Books
    'com.audible.application', // Audible (audiobooks)
    'com.overdrive.mobile.android.libby', // Libby
    'com.goodreads', // Goodreads
    'com.grammarly.android', // Grammarly
    'com.merriamwebster', // Merriam Webster Dictionary
    'com.dictionary', // Dictionary.com
    'com.fiete.world.a', // Fiete World
    'com.teachyourmonstertoread', // Teach Your Monster to Read
    'com.speakaboos.kidsscreentime', // Speakaboos
    'com.epic.android', // Epic Reading
    
    // Science & Creativity
    'com.nasa.app', // NASA
    'com.brainpop.android', // BrainPOP
    'com.noggin.app', // Noggin
    'com.pbskids.video', // PBS Kids
    'com.toca.hairsalon', // Toca Boca (creative)
    'com.tocaboca.tocalife', // Toca Life
    'com.lego.education.spike', // LEGO Education
    'com.adobe.reader', // Adobe Reader
    'com.canva.editor', // Canva
    'com.sketchbook', // Sketchbook
  };

  // Comprehensive Entertainment Apps
  static const Set<String> entertainmentApps = {
    // Video Streaming
    'com.google.android.youtube', // YouTube
    'com.google.android.youtube.kids', // YouTube Kids
    'com.netflix.mediaclient', // Netflix
    'com.amazon.avod.thirdpartyclient', // Prime Video
    'com.disney.disneyplus', // Disney+
    'com.hulu.plus', // Hulu
    'com.hbomax', // HBO Max
    'com.peacocktv.peacockandroid', // Peacock
    'com.apple.android.music', // Apple TV
    'com.crunchyroll.crunchyroid', // Crunchyroll
    'com.tubitv', // Tubi
    'com.pluto.android', // Pluto TV
    'com.plexapp.android', // Plex
    'com.roku.remote', // Roku
    'com.sling', // Sling TV
    
    // Social Media
    'com.instagram.android', // Instagram
    'com.zhiliaoapp.musically', // TikTok
    'com.snapchat.android', // Snapchat
    'com.facebook.katana', // Facebook
    'com.twitter.android', // Twitter/X
    'com.discord', // Discord
    'com.reddit.frontpage', // Reddit
    'com.pinterest', // Pinterest
    'com.whatsapp', // WhatsApp
    'com.telegeram.messenger', // Telegram
    'com.tumblr', // Tumblr
    'com.tinder', // Tinder
    'com.bumble.app', // Bumble
    
    // Games (Major ones)
    'com.roblox.client', // Roblox
    'com.mojang.minecraftpe', // Minecraft
    'com.king.candycrushsaga', // Candy Crush
    'com.king.candycrushsodasaga', // Candy Crush Soda
    'com.supercell.clashofclans', // Clash of Clans
    'com.supercell.clashroyale', // Clash Royale
    'com.supercell.brawlstars', // Brawl Stars
    'com.supercell.hayday', // Hay Day
    'com.ea.game.pvz2', // Plants vs Zombies
    'com.ea.games.simsfreeplay', // Sims
    'com.ea.gp.fifamobile', // FIFA Mobile
    'com.ea.ios.fifa15', // FIFA
    'com.epicgames.fortnite', // Fortnite
    'com.activision.callofduty.shooter', // Call of Duty Mobile
    'com.pubg.mobile', // PUBG Mobile
    'com.pubg.newstate', // PUBG New State
    'com.garena.game.codm', // Garena CoD
    'com.garena.freefire', // Free Fire
    'com.garena.freefiremax', // Free Fire Max
    'com.mobilelegends.mg', // Mobile Legends
    'com.tencent.ig', // PUBG variants
    'com.tencent.mm', // WeChat Games
    'com.dts.freefire', // Free Fire variants
    'com.blizzard.arc', // Blizzard games
    'com.nianticlabs.pokemongo', // Pokemon GO
    'com.nianticlabs.ingress', // Ingress
    'com.nianticlabs.pikmin', // Pikmin Bloom
    'com.ubisoft.hungryshark', // Hungry Shark
    'com.ubisoft.assassinscreed', // Assassin's Creed
    'com.miniclip.eightballpool', // 8 Ball Pool
    'com.miniclip.agar', // Agar.io
    'com.miniclip.slither', // Slither.io
    'com.rovio.angrybirds', // Angry Birds
    'com.rovio.baba', // Angry Birds variants
    'com.imangi.templerun', // Temple Run
    'com.imangi.templerun2', // Temple Run 2
    'com.sega.sonic1', // Sonic
    'com.nintendo.zara', // Nintendo games
    'com.nintendo.zaka', // Mario Kart
    'com.nintendo.zaca', // Animal Crossing
    'com.squareenix.finalfantasy', // Final Fantasy
    'com.ea.gp.apexlegendsmobile', // Apex Legends
    'com.riotgames.league', // League of Legends
    'com.riotgames.teamfighttactics', // TFT
    'com.riotgames.league.wildrift', // Wild Rift
    'com.tencent.tmgp.sgame', // Arena of Valor
    'com.netease.onmyoji', // Onmyoji
    'com.netease.identity', // Identity V
    'com.netease.harrypotter', // Harry Potter Magic Awakened
    'com.brawlstars.android', // Brawl Stars
    'com.halfbrick.fruitninja', // Fruit Ninja
    'com.halfbrick.jetpackjoyride', // Jetpack Joyride
    'com.outfit7.mytalkingtom', // Talking Tom
    'com.outfit7.mytalkingangela', // Talking Angela
    'com.ketchapp.game', // Ketchapp games
    'com.voodoo.game', // Voodoo games
    'com.homa.game', // Homa Games
    'com.saygame.game', // SayGames
    
    // Music & Audio
    'com.spotify.music', // Spotify
    'com.google.android.apps.youtube.music', // YouTube Music
    'com.amazon.mp3', // Amazon Music
    'com.pandora.android', // Pandora
    'com.soundcloud.android', // SoundCloud
    'com.audiomack', // Audiomack
    'com.shazam.android', // Shazam
    'com.smule.sing', // Smule
    
    // Other Entertainment
    'com.google.android.play.games', // Google Play Games
    'com.google.android.apps.tachyon', // Google Duo (if used for fun)
    'com.kuaishou.video', // Kwai
    'com.kakao.talk', // KakaoTalk
    'com.linecorp.line', // LINE
    'com.viber.voip', // Viber
    'com.sonyericsson.android.facebook', // Facebook Lite
    'com.facebook.lite', // Facebook Lite
    'com.instagram.lite', // Instagram Lite
    'com.tencent.mobileqq', // QQ
    'com.sina.weibo', // Weibo
    'com.yy.yymeet', // YY
    'com.bigolive.live', // Bigo Live
    'com.streamlabs.chat', // Streaming apps
    'com.twitch.android', // Twitch
    
    // Web Browsers (usually entertainment unless specified educational)
    'com.android.chrome', // Chrome
    'org.mozilla.firefox', // Firefox
    'com.opera.browser', // Opera
    'com.microsoft.emmx', // Edge
    'com.duckduckgo.mobile.android', // DuckDuckGo
    'com.brave.browser', // Brave
  };

  static String categorize(String packageName) {
    if (educationApps.contains(packageName)) return 'education';
    if (entertainmentApps.contains(packageName)) return 'entertainment';
    return 'other'; // System apps, utilities, etc.
  }
}