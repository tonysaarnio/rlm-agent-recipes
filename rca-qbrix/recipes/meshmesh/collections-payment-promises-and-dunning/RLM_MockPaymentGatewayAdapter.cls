/**
 * Mock payment gateway adapter for TEST/DEMO orgs only.
 * Approves every request without any external callout so Billing payment
 * promises, saved payment methods and payment batch runs can be validated
 * without a live payment processor. Never use in production.
 */
global with sharing class RLM_MockPaymentGatewayAdapter implements commercepayments.PaymentGatewayAdapter {
    global commercepayments.GatewayResponse processRequest(commercepayments.PaymentGatewayContext ctx) {
        commercepayments.RequestType t = ctx.getPaymentRequestType();
        commercepayments.PaymentGatewayRequest req = ctx.getPaymentRequest();
        String ref = 'MOCK-' + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        commercepayments.SalesforceResultCodeInfo ok =
            new commercepayments.SalesforceResultCodeInfo(commercepayments.SalesforceResultCode.Success);
        if (t == commercepayments.RequestType.Tokenize) {
            commercepayments.PaymentMethodTokenizationResponse r = new commercepayments.PaymentMethodTokenizationResponse();
            r.setGatewayToken('tok_' + ref);
            r.setGatewayResultCode('success');
            r.setSalesforceResultCodeInfo(ok);
            return r;
        } else if (t == commercepayments.RequestType.Sale) {
            commercepayments.SaleRequest s = (commercepayments.SaleRequest) req;
            commercepayments.SaleResponse r = new commercepayments.SaleResponse();
            r.setAmount(s.amount); r.setGatewayReferenceNumber(ref); r.setGatewayResultCode('success');
            r.setGatewayDate(System.now()); r.setSalesforceResultCodeInfo(ok);
            return r;
        } else if (t == commercepayments.RequestType.Authorize) {
            commercepayments.AuthorizationRequest a = (commercepayments.AuthorizationRequest) req;
            commercepayments.AuthorizationResponse r = new commercepayments.AuthorizationResponse();
            r.setAmount(a.amount); r.setGatewayReferenceNumber(ref); r.setGatewayAuthCode('AUTH');
            r.setGatewayResultCode('success'); r.setGatewayDate(System.now()); r.setSalesforceResultCodeInfo(ok);
            return r;
        } else if (t == commercepayments.RequestType.Capture) {
            commercepayments.CaptureRequest c = (commercepayments.CaptureRequest) req;
            commercepayments.CaptureResponse r = new commercepayments.CaptureResponse();
            r.setAmount(c.amount); r.setGatewayReferenceNumber(ref); r.setGatewayResultCode('success');
            r.setGatewayDate(System.now()); r.setSalesforceResultCodeInfo(ok);
            return r;
        } else if (t == commercepayments.RequestType.ReferencedRefund) {
            commercepayments.ReferencedRefundRequest f = (commercepayments.ReferencedRefundRequest) req;
            commercepayments.ReferencedRefundResponse r = new commercepayments.ReferencedRefundResponse();
            r.setAmount(f.amount); r.setGatewayReferenceNumber(ref); r.setGatewayResultCode('success');
            r.setGatewayDate(System.now()); r.setSalesforceResultCodeInfo(ok);
            return r;
        } else if (t == commercepayments.RequestType.AuthorizationReversal) {
            commercepayments.AuthorizationReversalRequest v = (commercepayments.AuthorizationReversalRequest) req;
            commercepayments.AuthorizationReversalResponse r = new commercepayments.AuthorizationReversalResponse();
            r.setAmount(v.amount); r.setGatewayReferenceNumber(ref); r.setGatewayResultCode('success');
            r.setGatewayDate(System.now()); r.setSalesforceResultCodeInfo(ok);
            return r;
        }
        return new commercepayments.GatewayErrorResponse('400', 'Unsupported request type: ' + t);
    }
}
