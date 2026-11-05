package app.poruch.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.poruch.android.R
import app.poruch.domain.Gathering
import app.poruch.domain.RefundPolicy

/** Правила повернення онлайн-події людськими словами; онлайн-подія без правил (стара) — null. */
@Composable
fun refundText(policy: RefundPolicy?): String? = policy?.let {
    val rule = when (it) {
        RefundPolicy.BEFORE_48H -> R.string.refund_before_48h
        RefundPolicy.BEFORE_24H -> R.string.refund_before_24h
        RefundPolicy.CANCEL_ONLY -> R.string.refund_cancel_only
    }
    stringResource(rule) + " " + stringResource(R.string.refund_organizer_cancels)
}

/** Коли платять (`events.prepay`, 20261125190000): під ціною на деталях і на панелі. Онлайн-подія — своє. */
@Composable
fun payWhenText(room: Gathering): String = stringResource(
    when {
        room.payOnline -> R.string.price_online
        room.prepay -> R.string.price_prepay
        else -> R.string.price_at_meeting
    }
)
