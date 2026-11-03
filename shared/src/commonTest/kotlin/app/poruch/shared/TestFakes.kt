package app.poruch.shared

import app.poruch.account.AccountActions
import app.poruch.domain.*
import app.poruch.events.EventActions
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow

// Підробки для тестів [PoruchApp]: усе в пам'яті, з лічильниками викликів і перемикачами збоїв.

internal class Auth: AuthRepository {
    override val session=MutableStateFlow<UserSession?>(UserSession("user","token","refresh",9999999999))
    override suspend fun signIn(email:String,password:String) {}
    /** Чи повертає бекенд сесію одразу; без підтвердження пошти — ні. */
    var signUpSignsIn=true
    /** Дата, з якою пішла реєстрація; null — галочка. */
    var signedUpWith:String?="unset"
    override suspend fun signUp(email:String,password:String,name:String,birthDate:String?):Boolean {
        signedUpWith=birthDate
        if(signUpSignsIn) session.value=UserSession("fresh","token","refresh",9999999999)
        return signUpSignsIn
    }
    val codesSent=mutableListOf<String>()
    override suspend fun sendCode(email:String) { codesSent+=email }
    /** Єдиний код, який підробка приймає; вхід ним дає сесію [codeUser]. */
    var validCode="123456"
    var codeUser="code-user"
    override suspend fun verifyCode(email:String,code:String) {
        if(code!=validCode) fail(AppError.InvalidCode)
        session.value=UserSession(codeUser,"token","refresh",9999999999,setOf("email"),setOf("otp"))
    }
    /** Сервер не впізнав прострочений токен: локально вихід усе одно відбувся. */
    var signOutRefused=false
    override suspend fun signOut() { session.value=null; if(signOutRefused) fail(AppError.SessionRequired) }
    override suspend fun accessToken()=session.value?.accessToken
    override suspend fun requestPasswordReset(email:String) {}
    var updated=false
    /** Поточний пароль, з яким пішла зміна: його звіряє й сервер. */
    var updatedWithCurrent:String?=null
    override suspend fun updatePassword(password:String,current:String?) { updated=true; updatedWithCurrent=current }
    override suspend fun handleCallback(url:String):Boolean { session.value=UserSession("recovered","new","refresh",9999999999); return true }
    /** Єдиний пароль, який підробка вважає правильним; null — приймає будь-який. */
    var currentPassword:String?=null
    override suspend fun verifyPassword(password: String) { if(currentPassword!=null&&password!=currentPassword) fail(AppError.InvalidCredentials) }
    var deletedWithAppleCode:String?=null
    var deletedWithPassword:String?=null
    var deleted=false
    override suspend fun deleteAccount(password:String?,appleAuthorizationCode:String?) { deleted=true; deletedWithPassword=password; deletedWithAppleCode=appleAuthorizationCode; session.value = null }
    override fun idTokenNonce()="hashed-nonce"
    /** Сесія, яку дасть вхід ID-токеном: провайдер — з неї. */
    var idTokenUser="oauth-user"
    override suspend fun signInWithIdToken(provider:IdProvider,idToken:String) { session.value=UserSession(idTokenUser,"token","refresh",9999999999,setOf(provider.key)) }
}

/** Підробка реалізує всі п'ять інтерфейсів, бо [PoruchApp] користується всіма. */
internal class Events: EventDiscovery, SavedEvents, EventAuthoring, EventParticipation, EventRequests, EventChat {
    val sent=mutableListOf<Pair<String,String>>()
    var chatMessages=emptyList<ChatMessage>()
    var offlineChat=false
    val readThreads=mutableListOf<String?>()
    override suspend fun messages(eventId:String,after:String?,thread:String?):List<ChatMessage> { if(offlineChat) fail(AppError.Network); readThreads+=thread; return chatMessages.filter { after==null || it.createdAt>after } }
    var failSend=false
    var slowSend=false
    val sentThreads=mutableListOf<String?>()
    val sentImages=mutableListOf<String?>()
    override suspend fun send(eventId:String,body:String,thread:String?,image:String?):String { if(slowSend) delay(100); if(failSend) fail(AppError.Network); sent+=eventId to body; sentThreads+=thread; sentImages+=image; val m=ChatMessage("m${sent.size}",eventId,"user","Я",null,body,"2026-09-16T10:0${sent.size}:00Z",image=image); chatMessages=chatMessages+m; return m.id }
    val uploadedProofs=mutableListOf<Pair<String,ByteArray>>()
    var proofFiles=emptyMap<String,ByteArray>()
    override suspend fun uploadProof(eventId:String,jpeg:ByteArray):String { val path="user/$eventId/p${uploadedProofs.size+1}.jpg"; uploadedProofs+=path to jpeg; return path }
    val proofDownloads=mutableListOf<String>()
    override suspend fun proof(path:String):ByteArray { proofDownloads+=path; return proofFiles[path] ?: fail(AppError.NotOwner) }
    override suspend fun delete(messageId:String) { chatMessages=chatMessages.filterNot { it.id==messageId } }
    var unreadChats=emptyList<ChatUnread>()
    val readMarks=mutableListOf<String>()
    override suspend fun unread()=unreadChats
    val readMarkThreads=mutableListOf<String?>()
    override suspend fun markRead(eventId:String,thread:String?) { readMarks+=eventId; readMarkThreads+=thread }
    var questions=emptyList<QuestionThread>()
    val questionCalls=mutableListOf<String>()
    override suspend fun questions(eventId:String):List<QuestionThread> { questionCalls+=eventId; return questions }
    val queries=mutableListOf<EventQuery>()
    val cardRequests=mutableListOf<List<String>>()
    val createIds=mutableListOf<String>()
    val saves=mutableListOf<String>()
    val unsaves=mutableListOf<String>()
    var failCreate=false
    var failSave=false
    var failDetails=false
    var results=emptyList<Event>()
    /** Скільки карток сервер кладе у відповідь одразу. Решта окремим запитом. */
    var inlineCards=Int.MAX_VALUE
    /** Що сервер відбирає за датою й «Від людей». За замовчуванням — нічого, як раніше. */
    var serves:(EventQuery,Event)->Boolean={ _,_ -> true }
    /** Чим падає видача; null — не падає. */
    var discoverError:AppError?=null
    /** Скільки їде видача. */
    var discoverDelay=100L
    override suspend fun discover(query:EventQuery):DiscoveryPage { queries+=query; delay(discoverDelay); discoverError?.let { fail(it) }; return page(results.filter { e -> query.text.let { it==null || it in e.title } && serves(query,e) },inlineCards) }
    override fun cached(query:EventQuery)=DiscoveryPage.Empty
    /** Картки, яких нема у видачі, але сервер їх віддає за id: подія, відкрита посиланням. */
    var offFeedCards=emptyList<Event>()
    /** Надгробок → жива подія, як `private.live_event_id` у `event_cards_by_ids`. */
    var mergedInto=emptyMap<String,String>()
    /** Скільки їде запит карток за id. */
    var cardsDelay=0L
    override suspend fun cards(ids:List<String>):List<Event> { cardRequests+=ids; delay(cardsDelay); val live=ids.map { mergedInto[it]?:it }; return (results+offFeedCards).filter { it.id in live } }
    var failPending=false
    var failFacts=false
    var detailsById=emptyMap<String,Event>()
    /** Запит на мертвому з'єднанні: висить, доки його не скасують. */
    var hangDetails=false
    var detailsCalls=0
    /** Деталі щойно створеної події: без них відкриття після публікації каже «подія недоступна» і перебиває банер. */
    var detailsOfCreated=false
    override suspend fun details(id:String):Event? {
        detailsCalls++; if(hangDetails) awaitCancellation(); if(failDetails) fail(detailsError)
        return detailsById[id] ?: createdDrafts.lastOrNull()?.takeIf { detailsOfCreated && id in createIds }?.let { d ->
            Event(id,d.title,d.description,d.category!!,d.city,d.address,d.startsAt,d.endsAt,d.timeZone,EventStatus.PUBLISHED,d.latitude,d.longitude,
                gathering=Gathering("user","Я",d.capacity,0,false))
        }
    }
    var detailsError:AppError=AppError.ServiceUnavailable
    var places=emptyList<Place>()
    val placeQueries=mutableListOf<Pair<String,EventQuery?>>()
    override suspend fun searchPlaces(text:String,city:String?,bounds:EventQuery?):List<Place> { placeQueries+=text to bounds; delay(50); return places.filter { it.name.lowercase().startsWith(text.lowercase()) } }
    var artists=emptyList<ArtistHit>()
    val artistQueries=mutableListOf<Pair<String,String?>>()
    override suspend fun searchArtists(text:String,city:String?):List<ArtistHit> { artistQueries+=text to city; delay(50); return artists.filter { it.name.lowercase().contains(text.lowercase()) } }
    var ofArtist=emptyMap<String,List<Event>>()
    var failArtistEvents=false
    override suspend fun artistEvents(artistId:String):List<Event> { delay(50); if(failArtistEvents) fail(AppError.Network); return ofArtist[artistId].orEmpty() }
    var radar=emptyList<ArtistRadar>()
    override suspend fun artistRadar(ids:List<String>,city:String?):List<ArtistRadar> { delay(50); return radar.filter { it.artistId in ids } }
    var atPlace=emptyMap<String,List<Event>>()
    var failPlaceEvents=false
    var placeEventCalls=0
    override suspend fun placeEvents(placeId:String):List<Event> { placeEventCalls++; if(failPlaceEvents) fail(AppError.Network); return atPlace[placeId].orEmpty() }
    override suspend fun safety(id:String):EventSafety? = null
    var companionCards=emptyList<CompanionCard>()
    override suspend fun companions(parentId:String)=companionCards
    /** «Хочу піти з компанією»: тизер, мої наміри по черзі, [mutual] — друга сторона вже сказала «Піти разом». */
    var teaser:CompanyTeaser?=null
    val intents=mutableListOf<Pair<String,Boolean>>()
    var mutual=false
    private fun intends(id:String)=intents.lastOrNull { it.first==id }?.second==true
    override suspend fun companyTeaser(eventId:String)=teaser?.copy(mine=intends(eventId))
    override suspend fun companyPeople(eventId:String)=
        if(intends(eventId)) listOf(CompanyPerson("anna","Анна",null,null,null,emptyList(),0,false,mutual,null)) else emptyList()
    override suspend fun setCompanyIntent(id:String,on:Boolean):Int { intents+=id to on; return teaser?.count?:0 }
    override suspend fun companyYes(id:String,userId:String)=CompanyMatch(mutual,if(mutual) "c9" else null)
    /** Запрошення: токен → (подія, хто кличе), як `invite_inviter`; [failInvite] — сервер відмовив створити. */
    var invites=mapOf<String,Pair<String,Inviter>>()
    var failInvite=false
    val invited=mutableListOf<String>()
    override suspend fun inviter(token:String,eventId:String)=invites[token]?.takeIf { it.first==eventId }?.second
    override suspend fun invite(id:String):String { if(failInvite) fail(AppError.TooManyAttempts); invited+=id; return "Tok_${id}_0000000000000000".take(22) }
    var districts=emptyList<District>()
    val districtCalls=mutableListOf<String>()
    override suspend fun districts(city:String):List<District> { districtCalls+=city; return districts.filter { it.city==city } }
    val companionsCreated=mutableListOf<List<Any?>>()
    val companionsMoved=mutableListOf<Pair<String,String>>()
    override suspend fun moveCompanion(id:String,meetAt:String) { companionsMoved+=id to meetAt }
    override suspend fun createCompanion(parentId:String,meetAt:String,note:String?,capacity:Int):String {
        companionsCreated+=listOf(parentId,meetAt,note,capacity)
        companionCards=companionCards+CompanionCard("c1",meetAt,"Europe/Kyiv",note,capacity,0,Membership.NONE,true)
        return "c1"
    }
    var mine=emptyList<Event>()
    var offlineMine=false
    var cachedMineValue:CachedMine?=null
    override suspend fun myEvents():List<Event> { if(offlineMine) fail(AppError.Network); return mine }
    override fun cachedMine()=cachedMineValue
    override suspend fun attendees(id:String)=emptyList<Attendee>()
    override fun clearPrivateCache() {}
    override suspend fun savedIds()=emptyList<String>()
    override suspend fun save(id:String) { delay(100); saves+=id; if(failSave) fail(AppError.Network) }
    override suspend fun unsave(id:String) { delay(100); unsaves+=id; if(failSave) fail(AppError.Network) }
    /** Чернетки, з якими пішли `create_event` і `update_event`, по черзі. */
    val createdDrafts=mutableListOf<EventDraft>()
    val updatedDrafts=mutableListOf<EventDraft>()
    var failUpdate=false
    /** Чим відмовляє `update_event`, коли [failUpdate]: мережа — відповіді не дочекались, інше — явна відмова. */
    var updateError:AppError=AppError.Network
    /** Чим відмовляє `create_event`; null — не відмовляє. */
    var createError:AppError?=null
    override suspend fun create(id:String,draft:EventDraft):String { createIds+=id; createdDrafts+=draft; if(failCreate) fail(AppError.Network); createError?.let { fail(it) }; return id }
    override suspend fun update(id:String,draft:EventDraft):String { updatedDrafts+=draft; if(failUpdate) fail(updateError); return id }
    override suspend fun cancel(id:String) {}
    /** Що й куди вантажили (`photo:…`, `video:…`, `copy:…`), по черзі; [failUploads] — ключі, на яких сховище падає. */
    val uploads=mutableListOf<String>()
    var failUploads=emptySet<String>()
    val deletedFiles=mutableListOf<String>()
    /** Прогрес, який бачила кожна завантажка: [AppState.mediaUpload] на її початку. */
    var progress:(()->MediaUpload?)?=null
    val progressSeen=mutableListOf<MediaUpload?>()
    private fun stored(key:String,eventId:String):String {
        progressSeen+=progress?.invoke(); uploads+=key
        if(key in failUploads) fail(AppError.ImageUploadFailed)
        return "https://test.invalid/$eventId/${uploads.size}-${key.substringBefore(':')}"
    }
    override suspend fun uploadImage(eventId:String,bytes:ByteArray,contentType:String)=stored("photo:${bytes.decodeToString()}",eventId)
    override suspend fun uploadVideo(eventId:String,bytes:ByteArray)=stored("video:${bytes.decodeToString()}",eventId)
    override suspend fun copyMedia(url:String,eventId:String)=stored("copy:$url",eventId)
    override suspend fun deleteImage(url:String) { deletedFiles+=url }
    /** Що відповідає `parse-announcement`; [announceError] — чим падає. */
    var announced=AnnouncementFill("Клуб","Читаємо разом",EventCategory.SOCIAL)
    var announceError:AppError?=null
    val announceCalls=mutableListOf<List<String>>()
    override suspend fun announcement(text:String,city:String,today:String,timeZone:String):AnnouncementFill {
        announceCalls+=listOf(text,city,today,timeZone); announceError?.let { fail(it) }; return announced
    }
    override suspend fun join(id:String) {}
    override suspend fun leave(id:String) {}
    override suspend fun waitlistIds()=emptyList<String>()
    override suspend fun joinWaitlist(id:String) {}
    override suspend fun leaveWaitlist(id:String) {}
    override suspend fun ratings(id:String) = emptyList<EventRating>()
    val rated=mutableListOf<String>()
    override suspend fun rate(id:String, score:Int, comment:String?, tags:List<RatingTag>) { rated+=id }
    override suspend fun joinRequests(id:String)=emptyList<Attendee>()
    var pending=emptyList<JoinRequest>()
    override suspend fun pendingRequests()=if(failPending) fail(AppError.ServiceUnavailable) else pending
    override suspend fun approveMember(eventId:String,userId:String) {}
    override suspend fun declineMember(eventId:String,userId:String) {}
}

/** Місто в пам'яті замість бази пристрою. */
internal class Cities(var stored:CityResult?=null, var manual:Boolean=false): CityStore {
    override fun read()=stored
    override fun write(city:CityResult, manual:Boolean) { stored=city; this.manual=manual }
    override fun manual()=manual
}
/** Підписки в пам'яті: сервер приймає з паузою, а список і стрічку віддає, як записав. */
internal class FollowsFake: Follows {
    var list=emptyList<Follow>()
    var feed=emptyList<Event>()
    val calls=mutableListOf<String>()
    var failFollow=false
    var failUnfollow=false
    var failMine=false
    var failSeen=false
    override suspend fun mine():List<Follow> { if(failMine) fail(AppError.Network); return list }
    override suspend fun follow(kind:FollowKind,targetId:String) {
        delay(100); if(failFollow) fail(AppError.Network)
        calls+="follow ${kind.key} $targetId"; list=list+Follow(kind,targetId,"srv $targetId",upcoming=2)
    }
    override suspend fun unfollow(kind:FollowKind,targetId:String) {
        delay(100); if(failUnfollow) fail(AppError.Network)
        calls+="unfollow ${kind.key} $targetId"; list=list.filterNot { it.kind==kind&&it.targetId==targetId }
    }
    override suspend fun upcoming()=feed
    override suspend fun seen() {
        delay(100); if(failSeen) fail(AppError.Network)
        calls+="seen"; list=list.map { it.copy(fresh=0) }
    }
}

/** Профілі в пам'яті: свій — [mine], чужі — [cards]; видалені файли записуються. */
internal class Profiles: ProfileRepository {
    var mine=Profile("user","Я",null,null,"2026-09-01T00:00:00Z",0,0,"me@example.invalid")
    var cards=mapOf<String,Profile>()
    var slow=emptySet<String>()
    val deleted=mutableListOf<String>()
    var uploads=0
    override suspend fun profile(userId:String):Profile? { if(userId in slow) delay(100); return if(userId==mine.userId) mine else cards[userId] }
    override suspend fun update(name:String,bio:String?) { mine=mine.copy(name=name.trim(),bio=ProfileRules.normalizeBio(bio)) }
    override suspend fun rename(name:String) { mine=mine.copy(name=name.trim()) }
    override suspend fun setAvatar(bytes:ByteArray,contentType:String):String { uploads++; return "https://test.invalid/avatar/$uploads.jpg".also { mine=mine.copy(avatarUrl=it) } }
    override suspend fun removeAvatar() { mine=mine.copy(avatarUrl=null) }
    override suspend fun deleteImage(url:String) { deleted+=url }
}

/** Скарги й блокування записуються, а не надсилаються. */
internal class Safety(var facts: AccountFacts = AccountFacts("1990-01-01")): SafetyRepository {
    var fail=false
    val reports=mutableListOf<Triple<String,ReportReason,String?>>()
    val blocked=mutableListOf<String>()
    var declared: String? = null
    override suspend fun account()=if(fail) fail(AppError.ServiceUnavailable) else facts
    override suspend fun declareBirthDate(date:String) { declared=date; facts=facts.copy(birthDate=date) }
    var adultConfirmations=0
    /** Галочка не дійшла (мережа): лишається запасний крок. */
    var adultFails=false
    override suspend fun confirmAdult() {
        if(adultFails) fail(AppError.Network)
        adultConfirmations++; facts=facts.copy(adultConfirmedAt=facts.adultConfirmedAt?:"2026-11-01T10:00:00Z")
    }
    override suspend fun reportEvent(eventId:String,reason:ReportReason,details:String?) { reports+=Triple(eventId,reason,details) }
    override suspend fun reportUser(userId:String,reason:ReportReason,details:String?) { reports+=Triple(userId,reason,details) }
    override suspend fun reportMessage(messageId:String,reason:ReportReason,details:String?) { reports+=Triple(messageId,reason,details) }
    override suspend fun block(userId:String) { blocked+=userId }
    override suspend fun unblock(userId:String) { blocked-=userId }
    override suspend fun blocked()=this.blocked.map { Attendee(it,"Заблокований",null) }
}

/** Копія відповідей на пристрої. Поле, щоб тест міг прочитати записане. */
internal class Answers(var stored: Taste = Taste()): TasteStore {
    override fun read() = stored
    override fun write(taste: Taste) { stored = taste }
}

/** Прапорець нагадувань пристрою в пам'яті. */
internal class Reminders(var on: Boolean = false, var digest: Boolean = true): ReminderPreferenceStore {
    override fun enabled() = on
    override fun setEnabled(enabled: Boolean) { on = enabled }
    override fun digestEnabled() = digest
    override fun setDigestEnabled(enabled: Boolean) { digest = enabled }
}

/** Закладки гостя в пам'яті замість `device:saved`. */
internal class GuestSaves(var stored:List<String> = emptyList()): GuestSavedStore {
    override fun ids()=stored
    override fun write(ids:List<String>) { stored=ids }
}

internal class GuestArtists(var stored:List<GuestArtist> = emptyList()): GuestArtistStore {
    override fun artists()=stored
    override fun saveArtists(artists:List<GuestArtist>) { stored=artists }
}

internal class Zones(var stored:List<Zone> = emptyList()): ZoneStore {
    override fun zones()=stored
    override fun saveZones(zones:List<Zone>) { stored=zones }
}

internal class Tickets(var stored:List<WalletTicket> = emptyList()): TicketStore {
    override fun all()=stored
    override fun write(tickets:List<WalletTicket>) { stored=tickets }
}

/** [PoruchApp] на підробках. Безпека, профілі, смак і нагадування — свої на кожен виклик, якщо тест не дав власних. */
internal fun testApp(
    events:Events, scope:CoroutineScope, auth:Auth=Auth(), creationIdentity:CreationIdentityStore?=null,
    safety:SafetyRepository?=Safety(), profiles:ProfileRepository?=Profiles(), taste:TasteStore?=Answers(), reminders:ReminderPreferenceStore?=Reminders(),
    cities:CityStore?=null, follows:Follows?=null, bought:SeenRequestStore?=null, guestSaves:GuestSavedStore?=null, goodDays:SeenRequestStore?=null,
    tickets:TicketStore?=null, guestArtists:GuestArtistStore?=null, zones:ZoneStore?=null
)=PoruchApp(
    events=events, saved=events, authoring=events, participation=events, requests=events, chat=events,
    auth=auth, cityStore=cities, follows=follows, boughtAsked=bought, guestSaves=guestSaves, goodDays=goodDays, tickets=tickets, guestArtists=guestArtists, zoneStore=zones,
    geo=object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },
    eventActions=EventActions(events,events,auth), accountActions=AccountActions(auth),
    safety=safety, profiles=profiles, tasteStore=taste, reminderStore=reminders, creationIdentity=creationIdentity, scope=scope
)

/** Ключ ідемпотентності в пам'яті, як `PersistentCreationIdentity`: той самий відбиток — той самий id, доки не [clear]. */
internal class Identities: CreationIdentityStore {
    private var pending:Pair<String,String>?=null
    var clears=0
    override fun idFor(draft:EventDraft):String {
        pending?.takeIf { it.first==draft.toString() }?.let { return it.second }
        return "id-${clears}-${draft.title.length}".also { pending=draft.toString() to it }
    }
    override fun clear() { clears++; pending=null }
}

/** Підробка віддає індекс і перші картки однією відповіддю, як сервер. */
internal fun page(events: List<Event>, inlineCards: Int = Int.MAX_VALUE) = DiscoveryPage(
    index = events.map {
        EventIndexEntry(
            id = it.id, latitude = it.latitude, longitude = it.longitude, category = it.category,
            startsAt = it.startsAt, timeZone = it.timeZone, title = it.title,
            origin = if (it.isCommunity) EventOrigin.COMMUNITY else EventOrigin.IMPORT,
            capacity = it.gathering?.capacity, attendeeCount = it.gathering?.attendeeCount ?: 0
        )
    },
    total = events.size, truncated = false, cards = events.take(inlineCards)
)
