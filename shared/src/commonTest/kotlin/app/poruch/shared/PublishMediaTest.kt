package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import kotlin.test.*

/** Фото й відео з публікацією (docs/organizers-1.5.md, «Фото й відео в редакторі»): подія → файли по черзі → `media`. */
@OptIn(ExperimentalCoroutinesApi::class)
class PublishMediaTest {
    private val walk=EventDraft("Прогулянка","Зустріч у центрі міста",EventCategory.OUTDOORS,"Київ","Поділ",50.45,30.5,"2090-01-01T10:00:00Z","2090-01-01T12:00:00Z","Europe/Kyiv",10)
    private fun bytes(text:String)=MediaBytes { text.encodeToByteArray() }
    private val photo=DraftMedia.Local("a",MediaKind.PHOTO,bytes("a"))
    private val copied=DraftMedia.Copied(EventMedia(MediaKind.PHOTO,"https://test.invalid/old/1.jpg"))
    private val video=DraftMedia.Local("v",MediaKind.VIDEO,bytes("v"),bytes("p"))

    /** Порядок чернетки зберігається; «Завантажуємо N з M» — на кожен файл, відео з постером — один файл. */
    @Test fun filesFollowTheEventInOrder()=runTest {
        val events=Events().apply { detailsOfCreated=true }; val app=testApp(events,backgroundScope)
        events.progress={ app.state.value.mediaUpload }
        runCurrent(); app.createEvent(walk.copy(media=listOf(photo,copied,video))); runCurrent()

        assertEquals(listOf("photo:a","copy:https://test.invalid/old/1.jpg","photo:p","video:v"),events.uploads)
        assertEquals(listOf<MediaUpload?>(MediaUpload(1,3),MediaUpload(2,3),MediaUpload(3,3),MediaUpload(3,3)),events.progressSeen)
        val id=events.createIds.single()
        assertEquals(
            listOf(
                EventMedia(MediaKind.PHOTO,"https://test.invalid/$id/1-photo"),
                EventMedia(MediaKind.PHOTO,"https://test.invalid/$id/2-copy"),
                EventMedia(MediaKind.VIDEO,"https://test.invalid/$id/4-video","https://test.invalid/$id/3-photo")
            ),
            events.updatedDrafts.single().media!!.map { (it as DraftMedia.Remote).media },
            "one update_event with every file"
        )
        assertEquals(id,app.state.value.completedEventId)
        assertEquals(AppNotice.Told(AppMessage.EVENT_PUBLISHED),app.state.value.notice)
        assertNull(app.state.value.mediaUpload)
        app.close()
    }

    /** Ключ чернетки живе, поки файли вантажаться: перезапуск посеред них повторить `create_event` з тим самим id. */
    @Test fun theCreationKeyOutlivesTheUploads()=runTest {
        val events=Events().apply { detailsOfCreated=true }; val identities=Identities()
        val app=testApp(events,backgroundScope,creationIdentity=identities)
        val clearsDuringUploads=mutableListOf<Int>()
        events.progress={ clearsDuringUploads+=identities.clears; null }
        runCurrent(); app.createEvent(walk.copy(media=listOf(photo))); runCurrent()
        assertEquals(listOf(0),clearsDuringUploads)
        assertEquals(1,identities.clears)
        app.close()
    }

    /** Відео не завантажилось: подія вже є й лишається, постер прибрано, решта файлів — у події. */
    @Test fun aFailedFileDoesNotUndoTheEvent()=runTest {
        val events=Events().apply { detailsOfCreated=true }; val app=testApp(events,backgroundScope)
        events.failUploads=setOf("video:v")
        runCurrent(); app.createEvent(walk.copy(media=listOf(photo,video))); runCurrent()

        val id=events.createIds.single()
        assertEquals(listOf("https://test.invalid/$id/2-photo"),events.deletedFiles,"the poster without its video")
        assertEquals(listOf(MediaKind.PHOTO),events.updatedDrafts.single().media!!.map { it.kind })
        assertEquals(id,app.state.value.completedEventId)
        assertEquals(AppNotice.MediaFailed(1),app.state.value.notice)
        app.close()
    }

    /** Жоден файл не ліг — другий запит нічого б не змінив. */
    @Test fun noFileNoMediaUpdate()=runTest {
        val events=Events().apply { detailsOfCreated=true }; val app=testApp(events,backgroundScope)
        events.failUploads=setOf("photo:a")
        runCurrent(); app.createEvent(walk.copy(media=listOf(photo))); runCurrent()
        assertTrue(events.updatedDrafts.isEmpty())
        assertEquals(AppNotice.MediaFailed(1),app.state.value.notice)
        app.close()
    }

    /** Сервер відмовив у `media` — файли прибрано; відповіді не дочекались — лишаємо: сервер міг їх зберегти. */
    @Test fun onlyARefusalDiscardsTheFiles()=runTest {
        val events=Events().apply { detailsOfCreated=true; failUpdate=true; updateError=AppError.Rejected }
        val app=testApp(events,backgroundScope)
        runCurrent(); app.createEvent(walk.copy(media=listOf(photo,video))); runCurrent()
        assertEquals(3,events.deletedFiles.size)
        assertEquals(events.createIds.single(),app.state.value.completedEventId)
        assertEquals(AppNotice.MediaFailed(2),app.state.value.notice)

        events.updateError=AppError.Network; events.deletedFiles.clear()
        app.createEvent(walk.copy(title="Друга прогулянка",media=listOf(photo))); runCurrent()
        assertTrue(events.deletedFiles.isEmpty(),"a timeout keeps the files")
        assertEquals(AppNotice.MediaFailed(1),app.state.value.notice)
        app.close()
    }

    /** Без нових файлів — один запит, як раніше. */
    @Test fun noNewFilesNoSecondRequest()=runTest {
        val events=Events(); val app=testApp(events,backgroundScope)
        runCurrent(); app.createEvent(walk); runCurrent()
        assertTrue(events.updatedDrafts.isEmpty())
        assertTrue(events.uploads.isEmpty())
        app.close()
    }

    private val kept=EventMedia(MediaKind.PHOTO,"https://test.invalid/e1/kept.jpg")
    private val dropped=EventMedia(MediaKind.VIDEO,"https://test.invalid/e1/v.mp4","https://test.invalid/e1/p.jpg")
    /** Подія з повними медіа, як її віддає `event_details`. */
    private val withMedia=Event("e1","Прогулянка","Зустріч у центрі міста",EventCategory.OUTDOORS,"Київ","Поділ","2090-01-01T10:00:00Z","2090-01-01T12:00:00Z",
        "Europe/Kyiv",EventStatus.PUBLISHED,50.45,30.52,dropped.poster,Gathering("user","Я",10,0,false),media=listOf(dropped,kept),mediaLoaded=true)
    private fun sent(events:Events)=events.updatedDrafts.last().media!!.map { (it as DraftMedia.Remote).media }

    /**
     * Правка з повних медіа ([PoruchApp.editDraft]): нові файли — до збереження, усе одним `update_event`; хибна чернетка
     * нічого не вантажить; прибрані з події файли зникають і зі сховища. Без розділу медіа (null) — нічого не чіпаємо.
     */
    @Test fun editingUploadsBeforeSavingAndDropsRemoved()=runTest {
        val events=Events(); val app=testApp(events,backgroundScope)
        events.detailsById=mapOf("e1" to withMedia)
        runCurrent()
        val draft=app.editDraft(withMedia)!!
        app.updateEvent("e1",draft.copy(title="",media=listOf(DraftMedia.Remote(kept),photo))); runCurrent()
        assertTrue(events.uploads.isEmpty())
        assertIs<AppNotice.Failed>(app.state.value.notice)

        app.updateEvent("e1",draft.copy(media=null)); runCurrent()
        assertNull(events.updatedDrafts.single().media,"an editor without media leaves them alone")
        assertEquals(withMedia.imageUrl,events.updatedDrafts.single().imageUrl,"and the cover too")
        assertTrue(events.deletedFiles.isEmpty())

        app.updateEvent("e1",draft.copy(media=listOf(DraftMedia.Remote(kept),photo))); runCurrent()
        assertEquals(listOf("photo:a"),events.uploads)
        assertEquals(listOf(kept,EventMedia(MediaKind.PHOTO,"https://test.invalid/e1/1-photo")),sent(events))
        assertNull(events.updatedDrafts.last().imageUrl,"the server takes the cover from the media")
        assertEquals(setOf(dropped.url,dropped.poster),events.deletedFiles.toSet(),"the removed video and its poster")
        assertEquals(AppNotice.Told(AppMessage.CHANGES_SAVED),app.state.value.notice)
        app.close()
    }

    /** Поки редактор був відкритий, у кабінеті додали фото Y: збереження з застосунку його не прибирає й не видаляє. */
    @Test fun aPhotoAddedOnTheWebMeanwhileStays()=runTest {
        val events=Events(); val app=testApp(events,backgroundScope)
        val draft=app.editDraft(withMedia)!!
        val y=EventMedia(MediaKind.PHOTO,"https://test.invalid/e1/y.jpg")
        events.detailsById=mapOf("e1" to withMedia.copy(media=listOf(dropped,kept,y)))
        runCurrent(); app.updateEvent("e1",draft.copy(media=listOf(DraftMedia.Remote(kept)))); runCurrent()
        assertEquals(listOf(kept,y),sent(events))
        assertEquals(setOf(dropped.url,dropped.poster),events.deletedFiles.toSet(),"only what the editor saw and removed")
        app.close()
    }

    /** У кабінеті тим часом прибрали відео X: застосунок не повертає мертве посилання і не видаляє вдруге. */
    @Test fun aVideoRemovedOnTheWebMeanwhileIsNotRevived()=runTest {
        val events=Events(); val app=testApp(events,backgroundScope)
        val draft=app.editDraft(withMedia)!!
        events.detailsById=mapOf("e1" to withMedia.copy(media=listOf(kept),imageUrl=kept.url))
        runCurrent(); app.updateEvent("e1",draft.copy(media=draft.media!!+photo)); runCurrent()
        assertEquals(listOf(kept,EventMedia(MediaKind.PHOTO,"https://test.invalid/e1/1-photo")),sent(events))
        assertTrue(events.deletedFiles.isEmpty())
        app.close()
    }

    /**
     * Редактор з картки (деталі ще їхали): медіа порожні, обкладинку взято за фото, і додано нове. На сервері відео й фото
     * лишаються першими, нове — за ними, і жоден файл не видаляється.
     */
    @Test fun editingFromACardNeverLosesTheMedia()=runTest {
        val events=Events(); val app=testApp(events,backgroundScope)
        events.detailsById=mapOf("e1" to withMedia.copy(imageUrl=kept.url))
        val card=withMedia.copy(media=emptyList(),mediaLoaded=false,imageUrl=kept.url)
        runCurrent(); app.updateEvent("e1",app.editDraft(card)!!.let { it.copy(media=it.media!!+photo) }); runCurrent()
        assertEquals(listOf(dropped,kept,EventMedia(MediaKind.PHOTO,"https://test.invalid/e1/1-photo")),sent(events))
        assertTrue(events.deletedFiles.isEmpty())
        assertEquals(AppNotice.Told(AppMessage.CHANGES_SAVED),app.state.value.notice)
        app.close()
    }

    /** Подія з самими відео: обкладинка — постер першого, і з картки він не дублюється фото, навіть коли відео п'ять. */
    @Test fun aPosterCoverIsNotDuplicatedAsAPhoto()=runTest {
        val events=Events(); val app=testApp(events,backgroundScope)
        val videos=List(5) { EventMedia(MediaKind.VIDEO,"https://test.invalid/e1/$it.mp4","https://test.invalid/e1/$it.jpg") }
        events.detailsById=mapOf("e1" to withMedia.copy(media=videos,imageUrl=videos[0].poster))
        val card=withMedia.copy(media=emptyList(),mediaLoaded=false,imageUrl=videos[0].poster)
        runCurrent(); app.updateEvent("e1",app.editDraft(card)!!); runCurrent()
        assertEquals(videos,sent(events))
        assertEquals(AppNotice.Told(AppMessage.CHANGES_SAVED),app.state.value.notice)
        app.close()
    }

    /** Повних деталей не прочитали — нічого не вантажимо й не пишемо. З картки шостий файл — відмова до вивантаження. */
    @Test fun withoutTheDetailsNothingIsWritten()=runTest {
        val events=Events(); val app=testApp(events,backgroundScope)
        events.failDetails=true; events.detailsError=AppError.Network
        runCurrent(); app.updateEvent("e1",walk.copy(media=listOf(photo))); runCurrent()
        assertTrue(events.uploads.isEmpty()); assertTrue(events.updatedDrafts.isEmpty())
        assertEquals(AppNotice.Failed(AppError.Network),app.state.value.notice)

        events.failDetails=false
        events.detailsById=mapOf("e1" to withMedia.copy(media=List(5) { EventMedia(MediaKind.PHOTO,"https://test.invalid/e1/$it.jpg") }))
        app.updateEvent("e1",walk.copy(media=listOf(photo))); runCurrent()
        assertTrue(events.uploads.isEmpty()); assertTrue(events.updatedDrafts.isEmpty())
        assertEquals(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)),(app.state.value.notice as AppNotice.Failed).error)
        app.close()
    }

    /** Стара обкладинка з деталей стає першою в медіа, а фото з кабінету лишаються; шостому файлу місця нема — до вивантаження. */
    @Test fun theOldCoverPickerKeepsTheMedia()=runTest {
        val events=Events(); val app=testApp(events,backgroundScope)
        val fromWeb=EventMedia(MediaKind.VIDEO,"https://test.invalid/e1/v.mp4","https://test.invalid/e1/p.jpg")
        val event=Event(
            "e1","Прогулянка","Опис",EventCategory.OUTDOORS,"Київ","Поділ","2090-01-01T10:00:00Z","2090-01-01T12:00:00Z","Europe/Kyiv",
            EventStatus.PUBLISHED,50.45,30.52,null,Gathering("user","Я",10,0,false),media=listOf(fromWeb)
        )
        events.detailsById=mapOf("e1" to event)
        runCurrent(); app.uploadEventImage("e1","c".encodeToByteArray(),"image/jpeg"); runCurrent()
        assertEquals(listOf(MediaKind.PHOTO,MediaKind.VIDEO),events.updatedDrafts.single().media!!.map { it.kind })
        assertEquals(fromWeb,(events.updatedDrafts.single().media!![1] as DraftMedia.Remote).media)

        events.detailsById=mapOf("e1" to event.copy(media=emptyList()))
        app.uploadEventImage("e1","c".encodeToByteArray(),"image/jpeg"); runCurrent()
        assertNull(events.updatedDrafts.last().media,"without media — just the cover, as before")

        events.detailsById=mapOf("e1" to event.copy(media=List(5) { fromWeb })); events.uploads.clear()
        app.uploadEventImage("e1","c".encodeToByteArray(),"image/jpeg"); runCurrent()
        assertTrue(events.uploads.isEmpty())
        assertEquals(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)),(app.state.value.notice as AppNotice.Failed).error)
        app.close()
    }

    /** Відбиток чернетки — за ключем файлу, а не за байтами: повтор після збою бере той самий id. */
    @Test fun localFilesCompareByKey() {
        assertEquals(DraftMedia.Local("a",MediaKind.PHOTO,bytes("1")),DraftMedia.Local("a",MediaKind.PHOTO,bytes("2")))
        assertEquals(walk.copy(media=listOf(photo)).toString(),walk.copy(media=listOf(DraftMedia.Local("a",MediaKind.PHOTO,bytes("9")))).toString())
        assertEquals(listOf(DraftField.IMAGE_URL),walk.copy(media=List(6) { photo }).validate("2026-11-01T00:00:00Z"))
    }
}
